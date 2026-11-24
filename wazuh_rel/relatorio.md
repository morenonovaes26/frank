# Relatório Wazuh - últimos 60 dias

- Gerado em: 2026-11-23 16:33 UTC
- Período: 2026-09-24 a 2026-11-23
- Fonte: /mnt/wazuh-data/docker/volumes/single-node_wazuh_logs/_data/alerts (30 arquivos lidos)
- Linhas JSON inválidas ignoradas: 0

## Resumo

| Métrica | Valor |
|---|---|
| Total de alertas no período | 19050232 |
| Alertas com nível >= 12 | 115 |
| Agentes com alertas | 30 |
| Regras distintas disparadas | 2419 |
| Eventos de integridade de arquivos (FIM) | 27890 |
| Falhas de autenticação | 448845 |
| Eventos com sinal de DLP (total) | 11580 |

## Distribuição por nível de severidade

| Nível | Alertas |
|---|---|
| 12 | 115 |
| 11 | 127 |
| 10 | 62819 |
| 9 | 39117 |
| 8 | 1290 |
| 7 | 449291 |
| 6 | 1619748 |
| 5 | 1265811 |
| 4 | 393307 |
| 3 | 15218607 |

## Tendência diária (dias com maior volume)

| Data | Alertas | Críticos |
|---|---|---|
| 2026-09-28 | 1033765 | 4 |
| 2026-10-06 | 1028556 | 4 |
| 2026-10-05 | 979514 | 4 |
| 2026-10-02 | 950996 | 8 |
| 2026-09-30 | 916231 | 8 |
| 2026-09-29 | 903892 | 2 |
| 2026-10-20 | 893817 | 1 |
| 2026-10-07 | 880171 | 3 |
| 2026-09-25 | 877936 | 2 |
| 2026-10-08 | 858052 | 4 |

## Top 15 regras disparadas

| Regra | Descrição | Nível | Ocorrências |
|---|---|---|---|
| 60137 | Windows User Logoff. | 3 | 12986505 |
| 60106 | Windows logon success. | 3 | 2200865 |
| 60104 | Windows audit failure event. | 5 | 716211 |
| 510 | Host-based anomaly detection event (rootcheck). | 7 | 442588 |
| 60122 | Logon failure - Unknown user or bad password. | 5 | 434701 |
| 60107 | Failed attempt to perform a privileged operation. | 4 | 393183 |
| 92657 | Successful Remote Logon Detected - User:\renan.izoton - NTLM authentication, possible pass-the-hash attack - Possible RDP connection. Verify that LMTZ0131 is allowed to perform RDP connections | 6 | 69067 |
| 60205 | Multiple Windows audit failure events. | 10 | 42747 |
| 92657 | Successful Remote Logon Detected - User:\alice.aguiar - NTLM authentication, possible pass-the-hash attack - Possible RDP connection. Verify that LSC0016 is allowed to perform RDP connections | 6 | 40124 |
| 60602 | Windows application error event. | 9 | 38887 |
| 61102 | Windows System error event | 5 | 35229 |
| 31101 | Web server 400 error code. | 5 | 33420 |
| 92657 | Successful Remote Logon Detected - User:\LMTZ0131$ - NTLM authentication, possible pass-the-hash attack - Possible RDP connection. Verify that LMTZ0131 is allowed to perform RDP connections | 6 | 30530 |
| 92657 | Successful Remote Logon Detected - User:\tiago.baldan - NTLM authentication, possible pass-the-hash attack - Possible RDP connection. Verify that LITORAL-0176 is allowed to perform RDP connections | 6 | 24475 |
| 92657 | Successful Remote Logon Detected - User:\LMTZ0322$ - NTLM authentication, possible pass-the-hash attack - Possible RDP connection. Verify that LMTZ0322 is allowed to perform RDP connections | 6 | 22642 |

## Agentes com mais alertas

| Agente | Alertas | Falhas de autenticação | Eventos DLP |
|---|---|---|---|
| SRV-ADFOTUS01 | 10808936 | 40339 | 2 |
| BMW | 6377991 | 69722 | 0 |
| DTC-BD-02 | 1037563 | 322905 | 4 |
| srv-metabase | 438892 | 21 | 11457 |
| JETTA | 138512 | 811 | 0 |
| BORA | 60896 | 14980 | 2 |
| DTC-SAGA-HMG | 40305 | 0 | 0 |
| glpi | 34597 | 6 | 7 |
| defense | 33976 | 3 | 3 |
| PLUTAO | 19268 | 1 | 0 |
| WMS-Senior | 16577 | 4 | 0 |
| PARS | 8225 | 0 | 0 |
| CORSA | 7836 | 0 | 0 |
| DEFENSE-TESTE | 7207 | 0 | 3 |
| ct-n8n | 3615 | 0 | 0 |

## Grupos de regra mais frequentes

| Grupo | Ocorrências |
|---|---|
| windows | 18531896 |
| windows_security | 16795274 |
| authentication_success | 2206255 |
| win_evt_channel | 1619996 |
| 
      authentication_success | 1619734 |
| 
     | 1619734 |
| ossec | 472004 |
| rootcheck | 442715 |
| authentication_failed | 434801 |
| system_error | 74128 |
| windows_application | 72340 |
| windows_system | 44285 |
| web | 33535 |
| accesslog | 33510 |
| attack | 33456 |

## Táticas MITRE ATT&CK

| Tática | Ocorrências |
|---|---|
| Defense Evasion | 4679811 |
| Persistence | 4656548 |
| Privilege Escalation | 4654338 |
| Initial Access | 4654154 |
| Lateral Movement | 1622406 |
| Impact | 457396 |
| Credential Access | 14114 |
| Reconnaissance | 71 |

## Integridade de arquivos (FIM)

| Evento | Ocorrências |
|---|---|
| modified | 16139 |
| added | 6982 |
| deleted | 4769 |

Caminhos com mais alterações:

| Caminho | Eventos |
|---|---|
| HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\W32Time\SecureTimeLimits | 1949 |
| HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\W32Time\SecureTimeLimits\RunTime | 1184 |
| HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\W32Time\Config | 918 |
| HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\ASP.NET_4.0.30319\Names | 816 |
| HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\RestrictedServices\AppIso\FirewallRules | 608 |
| HKEY_LOCAL_MACHINE\Security\RXACT | 479 |
| HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules | 467 |
| HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\SharedAccess\Epoch | 388 |
| HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\BITS | 387 |
| HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\bam\State\UserSettings\S-1-5-18 | 341 |
| HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\DsmSvc\State | 319 |
| HKEY_LOCAL_MACHINE\Security\Policy\PolAdtEv | 304 |
| HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\bam\State\UserSettings\S-1-5-21-3306485205-3391387445-2848526961-7193 | 300 |
| HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\bam\State\UserSettings\S-1-5-21-3014903061-2811072902-2231301302-1603 | 282 |
| HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\bam\State\UserSettings\S-1-5-21-3306485205-3391387445-2848526961-10589 | 277 |

## Sinais de DLP

| Categoria | Eventos |
|---|---|
| contexto (canal de saída: USB, nuvem, webmail, upload) | 11318 |
| forte (palavra/padrão de dado sensível ou vazamento) | 198 |
| FIM em arquivo de documento/base | 64 |

Os eventos completos estão em `dlp_eventos.csv`. Primeiros 20 (mais recentes):

| Timestamp | Agente | Descrição | Caminho/Local |
|---|---|---|---|
| 2026-10-22T13:42:49 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:42:47 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:42:35 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:42:21 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:42:02 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:42:00 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:41:34 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:41:31 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:41:13 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:41:10 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:40:42 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:40:40 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:40:08 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:40:06 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:39:31 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:38:59 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:38:57 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:38:29 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:38:27 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |
| 2026-10-22T13:37:59 | srv-metabase | Host-based anomaly detection event (rootcheck). | rootcheck |

## Limitações e como interpretar

- O Wazuh não possui DLP nativo. Os sinais acima são heurísticas por palavras-chave, grupos de regra e caminhos de arquivo. Espere falsos positivos e valide antes de concluir.
- `alerts.json` contém só eventos que passaram pelo limiar `log_alert_level` do ossec.conf (padrão 3). Eventos de nível baixo não aparecem aqui. Use `--source archives` se o `<logall>` estiver ativo.
- Se o período tiver lacunas, verifique se os arquivos diários foram removidos por logrotate, pouco espaço em disco ou parada do serviço. Isso pode estar ligado aos problemas atuais.
- Os trechos (`full_log`) podem conter dados pessoais. Trate os CSVs como confidenciais.
