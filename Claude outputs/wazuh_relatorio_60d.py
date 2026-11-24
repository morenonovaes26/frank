#!/usr/bin/env python3
"""
Relatório de segurança, métricas e sinais de DLP a partir dos logs locais do Wazuh.

Executar NO SERVIDOR WAZUH (manager), como root. Só usa a biblioteca padrão do Python 3
e NÃO altera nada no Wazuh (somente leitura).

Uso:
  sudo python3 wazuh_relatorio_60d.py --days 60 --out /tmp/wazuh_relatorio
  sudo python3 wazuh_relatorio_60d.py --days 60 --out /tmp/wazuh_relatorio --source archives

Saída (dentro de --out):
  relatorio.md            resumo executivo e métricas
  alertas_por_dia.csv
  regras_top.csv
  agentes.csv
  alertas_criticos.csv    alertas com nível >= --critical-level
  dlp_eventos.csv         eventos com sinais de DLP (categorias explicadas no relatório)
  fim_eventos.csv         eventos de integridade de arquivos (syscheck)

ATENÇÃO: os CSVs contêm trechos do log (full_log). Trate a saída como confidencial.
"""

import argparse
import csv
import glob
import gzip
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timedelta, timezone

BASE_DIRS = {
    "alerts": "/var/ossec/logs/alerts",      # alertas (alerts.json) - padrão
    "archives": "/var/ossec/logs/archives",  # todos os eventos, se <logall> estiver ativo
}
FILE_RE = re.compile(r"ossec-(alerts|archive)-(\d{2})\.json(\.gz)?$")

# Sinais fortes de DLP: palavras/padrões que indicam dado sensível ou vazamento
DLP_STRONG = re.compile(
    r"dlp|data.?loss|exfil|\bpii\b|\bcpf\b|\bcnpj\b|credit.?card|"
    r"cart[aã]o de cr[eé]dito|sensitive.?data|dados sens[ií]veis|confidencial|confidential",
    re.I,
)
# Sinais de contexto: canais de saída de dados (mídia removível, nuvem, webmail, upload)
DLP_CONTEXT = re.compile(
    r"usb|removable|removív|pendrive|mass.?storage|dropbox|google.?drive|onedrive|"
    r"mega\.nz|wetransfer|webmail|gmail|upload|clipboard",
    re.I,
)
# Arquivos típicos de documentos/bases que merecem atenção quando alterados
SENSITIVE_FILE = re.compile(
    r"\.(pdf|docx?|xlsx?|csv|pptx?|zip|rar|7z|sql|bak|pst|ost|kdbx|key|pfx|p12)$", re.I
)


def parse_ts(value):
    """Converte o timestamp do Wazuh (ex.: 2026-11-20T10:00:00.123-0300)."""
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            return datetime.strptime(value, fmt)
        except (ValueError, TypeError):
            pass
    try:
        return datetime.fromisoformat(value)
    except (ValueError, TypeError):
        return None


def list_files(base_dir, cutoff_date):
    """Lista os arquivos diários (ano/Mês/dia) a partir da data de corte."""
    files = []
    for path in glob.glob(os.path.join(base_dir, "*", "*", "ossec-*-*.json*")):
        m = FILE_RE.search(os.path.basename(path))
        if not m:
            continue
        parts = path.split(os.sep)
        try:
            day = datetime.strptime(f"{parts[-3]} {parts[-2]} {m.group(2)}", "%Y %b %d").date()
        except (ValueError, IndexError):
            continue
        if day >= cutoff_date - timedelta(days=1):
            files.append((day, path))
    return [p for _, p in sorted(files)]


def open_any(path):
    if path.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, "r", encoding="utf-8", errors="replace")


def write_csv(path, header, rows):
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(header)
        w.writerows(rows)


def md_table(header, rows):
    if not rows:
        return "_Sem dados no período._\n"
    out = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    for r in rows:
        out.append("| " + " | ".join(str(c).replace("|", "/") for c in r) + " |")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description="Relatório Wazuh (últimos N dias)")
    ap.add_argument("--days", type=int, default=60)
    ap.add_argument("--out", default="./wazuh_relatorio")
    ap.add_argument("--source", choices=["alerts", "archives"], default="alerts")
    ap.add_argument("--critical-level", type=int, default=12)
    ap.add_argument("--base-dir", default=None,
                    help="Caminho alternativo para a pasta 'alerts' ou 'archives' (ex.: disco secundário)")
    args = ap.parse_args()

    base_dir = args.base_dir or BASE_DIRS[args.source]
    if not os.path.isdir(base_dir):
        sys.exit(f"Diretório não encontrado: {base_dir}. Execute como root no servidor Wazuh.")

    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(days=args.days)
    files = list_files(base_dir, cutoff.date())
    if not files:
        sys.exit(f"Nenhum arquivo de {args.source} encontrado nos últimos {args.days} dias em {base_dir}.")

    os.makedirs(args.out, exist_ok=True)

    total = 0
    bad_lines = 0
    by_level = Counter()
    by_day = Counter()
    by_day_crit = Counter()
    rules = Counter()
    rule_meta = {}
    agents = Counter()
    groups = Counter()
    tactics = Counter()
    fim_events = Counter()
    fim_paths = Counter()
    auth_fail_by_agent = Counter()
    critical_rows = []
    fim_rows = []
    dlp_rows = []
    dlp_cat = Counter()
    dlp_by_agent = Counter()

    for path in files:
        try:
            f = open_any(path)
        except OSError as exc:
            print(f"aviso: não foi possível abrir {path}: {exc}", file=sys.stderr)
            continue
        with f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    e = json.loads(line)
                except json.JSONDecodeError:
                    bad_lines += 1
                    continue

                ts = parse_ts(e.get("timestamp", ""))
                if ts is None or ts < cutoff:
                    continue

                rule = e.get("rule") or {}
                lvl = int(rule.get("level", 0) or 0)
                rid = str(rule.get("id", ""))
                desc = rule.get("description", "") or ""
                grp = rule.get("groups") or []
                agent = (e.get("agent") or {}).get("name", "(manager)")
                loc = e.get("location", "") or ""
                full = e.get("full_log", "") or ""
                sc = e.get("syscheck") or {}
                fpath = sc.get("path", "") or ""
                day = ts.strftime("%Y-%m-%d")

                total += 1
                by_level[lvl] += 1
                by_day[day] += 1
                rules[(rid, desc)] += 1
                rule_meta[(rid, desc)] = lvl
                agents[agent] += 1
                for g in grp:
                    groups[g] += 1
                for t in (rule.get("mitre") or {}).get("tactic", []) or []:
                    tactics[t] += 1
                if "authentication_failed" in grp or "authentication_failures" in grp:
                    auth_fail_by_agent[agent] += 1

                if lvl >= args.critical_level:
                    by_day_crit[day] += 1
                    critical_rows.append([ts.isoformat(), agent, rid, lvl, desc, loc])

                if sc:
                    ev = sc.get("event", "") or "desconhecido"
                    fim_events[ev] += 1
                    if fpath:
                        fim_paths[fpath] += 1
                    fim_rows.append([ts.isoformat(), agent, ev, fpath, lvl, desc])

                text = " ".join([desc, " ".join(grp), full, fpath, loc])
                category = None
                if DLP_STRONG.search(text):
                    category = "forte (palavra/padrão de dado sensível ou vazamento)"
                elif DLP_CONTEXT.search(text):
                    category = "contexto (canal de saída: USB, nuvem, webmail, upload)"
                elif sc and fpath and SENSITIVE_FILE.search(fpath):
                    category = "FIM em arquivo de documento/base"
                if category:
                    dlp_cat[category] += 1
                    dlp_by_agent[agent] += 1
                    dlp_rows.append([ts.isoformat(), agent, category, rid, lvl, desc,
                                     fpath or loc, full[:250].replace("\n", " ")])

    # ---- CSVs ----
    write_csv(os.path.join(args.out, "alertas_por_dia.csv"),
              ["data", "alertas", "alertas_criticos"],
              [[d, by_day[d], by_day_crit.get(d, 0)] for d in sorted(by_day)])
    write_csv(os.path.join(args.out, "regras_top.csv"),
              ["regra_id", "descricao", "nivel", "ocorrencias"],
              [[rid, desc, rule_meta[(rid, desc)], n] for (rid, desc), n in rules.most_common()])
    write_csv(os.path.join(args.out, "agentes.csv"),
              ["agente", "alertas", "falhas_autenticacao", "eventos_dlp"],
              [[a, n, auth_fail_by_agent.get(a, 0), dlp_by_agent.get(a, 0)]
               for a, n in agents.most_common()])
    write_csv(os.path.join(args.out, "alertas_criticos.csv"),
              ["timestamp", "agente", "regra_id", "nivel", "descricao", "localizacao"],
              sorted(critical_rows, reverse=True))
    write_csv(os.path.join(args.out, "dlp_eventos.csv"),
              ["timestamp", "agente", "categoria", "regra_id", "nivel", "descricao", "caminho_ou_local", "trecho"],
              sorted(dlp_rows, reverse=True))
    write_csv(os.path.join(args.out, "fim_eventos.csv"),
              ["timestamp", "agente", "evento", "caminho", "nivel", "descricao"],
              sorted(fim_rows, reverse=True))

    # ---- Relatório Markdown ----
    L = []
    L.append(f"# Relatório Wazuh - últimos {args.days} dias\n")
    L.append(f"- Gerado em: {now.strftime('%Y-%m-%d %H:%M')} UTC")
    L.append(f"- Período: {cutoff.strftime('%Y-%m-%d')} a {now.strftime('%Y-%m-%d')}")
    L.append(f"- Fonte: {base_dir} ({len(files)} arquivos lidos)")
    L.append(f"- Linhas JSON inválidas ignoradas: {bad_lines}\n")

    L.append("## Resumo\n")
    L.append(md_table(["Métrica", "Valor"], [
        ["Total de alertas no período", total],
        [f"Alertas com nível >= {args.critical_level}", len(critical_rows)],
        ["Agentes com alertas", len(agents)],
        ["Regras distintas disparadas", len(rules)],
        ["Eventos de integridade de arquivos (FIM)", sum(fim_events.values())],
        ["Falhas de autenticação", sum(auth_fail_by_agent.values())],
        ["Eventos com sinal de DLP (total)", len(dlp_rows)],
    ]))

    L.append("## Distribuição por nível de severidade\n")
    L.append(md_table(["Nível", "Alertas"], [[l, by_level[l]] for l in sorted(by_level, reverse=True)]))

    L.append("## Tendência diária (dias com maior volume)\n")
    top_days = sorted(by_day.items(), key=lambda x: x[1], reverse=True)[:10]
    L.append(md_table(["Data", "Alertas", "Críticos"], [[d, n, by_day_crit.get(d, 0)] for d, n in top_days]))

    L.append("## Top 15 regras disparadas\n")
    L.append(md_table(["Regra", "Descrição", "Nível", "Ocorrências"],
                      [[rid, desc, rule_meta[(rid, desc)], n] for (rid, desc), n in rules.most_common(15)]))

    L.append("## Agentes com mais alertas\n")
    L.append(md_table(["Agente", "Alertas", "Falhas de autenticação", "Eventos DLP"],
                      [[a, n, auth_fail_by_agent.get(a, 0), dlp_by_agent.get(a, 0)]
                       for a, n in agents.most_common(15)]))

    L.append("## Grupos de regra mais frequentes\n")
    L.append(md_table(["Grupo", "Ocorrências"], groups.most_common(15)))

    L.append("## Táticas MITRE ATT&CK\n")
    L.append(md_table(["Tática", "Ocorrências"], tactics.most_common(15)))

    L.append("## Integridade de arquivos (FIM)\n")
    L.append(md_table(["Evento", "Ocorrências"], fim_events.most_common()))
    L.append("Caminhos com mais alterações:\n")
    L.append(md_table(["Caminho", "Eventos"], fim_paths.most_common(15)))

    L.append("## Sinais de DLP\n")
    L.append(md_table(["Categoria", "Eventos"], dlp_cat.most_common()))
    L.append("Os eventos completos estão em `dlp_eventos.csv`. Primeiros 20 (mais recentes):\n")
    L.append(md_table(["Timestamp", "Agente", "Descrição", "Caminho/Local"],
                      [[r[0][:19], r[1], r[5], r[6]] for r in sorted(dlp_rows, reverse=True)[:20]]))

    L.append("## Limitações e como interpretar\n")
    L.append(
        "- O Wazuh não possui DLP nativo. Os sinais acima são heurísticas por palavras-chave, "
        "grupos de regra e caminhos de arquivo. Espere falsos positivos e valide antes de concluir.\n"
        "- `alerts.json` contém só eventos que passaram pelo limiar `log_alert_level` do ossec.conf "
        "(padrão 3). Eventos de nível baixo não aparecem aqui. Use `--source archives` se o "
        "`<logall>` estiver ativo.\n"
        "- Se o período tiver lacunas, verifique se os arquivos diários foram removidos por "
        "logrotate, pouco espaço em disco ou parada do serviço. Isso pode estar ligado aos "
        "problemas atuais.\n"
        "- Os trechos (`full_log`) podem conter dados pessoais. Trate os CSVs como confidenciais.\n"
    )

    with open(os.path.join(args.out, "relatorio.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(L))

    print(f"Concluído. {total} alertas em {args.days} dias. Saída em: {args.out}")
    print(f"Eventos com sinal de DLP: {len(dlp_rows)} | Críticos: {len(critical_rows)} | FIM: {sum(fim_events.values())}")


if __name__ == "__main__":
    main()
