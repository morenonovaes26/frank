# Assessment de Vulnerabilidades – Ideias e Arquitetura

## Objetivo

Descobrir ativos, identificar vulnerabilidades, priorizar por risco real (explorabilidade e exposição) e acompanhar a correção, usando a IA para triagem e explicação, não como substituto das fontes de dados.

## Fluxo proposto

1. **Inventário de ativos**: hosts, VMs, containers e serviços (base: `inventario.yaml`). Alimentar também com o que o Wazuh coleta.
2. **Descoberta externa**: consultar Shodan, Censys e urlscan.io para o domínio e IPs públicos, detectando portas e serviços expostos por engano.
3. **Scan interno**: Nuclei e/ou OpenVAS (Greenbone) contra as VMs e serviços, em janela agendada pelo n8n.
4. **Inventário de vulnerabilidades no endpoint**: módulo de Vulnerability Detection do Wazuh (CVEs de pacotes instalados nas VMs e agentes).
5. **Enriquecimento**: para cada CVE, buscar CVSS e CPE no NVD (NIST), EPSS (probabilidade de exploração) e se há exploração ativa no AlienVault OTX, GreyNoise e Pulsedive. Para hashes ou URLs suspeitas, usar VirusTotal, MalwareBazaar, Hybrid Analysis e URLhaus.
6. **Priorização**: score combinado (CVSS + EPSS + exposição externa + criticidade do ativo + exploração conhecida no KEV da CISA). Pode ser uma regra simples no n8n antes de qualquer IA.
7. **Triagem com IA (Ollama no pc-gpu)**: um modelo local resume o achado, explica o impacto para o ativo, sugere a correção e o plano de rollback. Dados sensíveis permanecem na rede interna.
8. **Tickets e acompanhamento**: criar caso no TheHive (um caso por CVE/ativo agrupado) com observables (IPs, domínios, hashes) analisados pelo Cortex.
9. **Relatório e métricas**: tempo médio de correção por severidade, ativos com maior dívida, tendência mensal.

## Ideias de módulos (priorizadas)

**Fase 1 – base rápida**
- Wazuh Vulnerability Detection em todos os agentes, com alertas por severidade crítica e alta.
- Workflow n8n diário que lê os alertas do Wazuh, enriquece com NVD e EPSS e grava um resumo.
- Enriquecimento de IPs de alertas com AbuseIPDB e GreyNoise (para reduzir ruído de scanners de internet).

**Fase 2 – exposição externa**
- Job semanal com Shodan/Censys sobre IPs e domínio públicos, comparando com o inventário (o que aparece na internet e não deveria).
- Checagem de certificados e cabeçalhos HTTP dos domínios publicados pelo NPM.
- urlscan.io para monitorar o domínio e subdomínios de phishing ou clones.

**Fase 3 – scan ativo e IA**
- Nuclei com templates atualizados, agendado, com resultados para o mesmo pipeline de priorização.
- OpenVAS/Greenbone se precisar de cobertura de rede mais ampla e relatórios formais.
- Agente de triagem com Ollama: recebe o achado priorizado e devolve resumo, impacto e passos de correção, com a fonte citada.
- Checagem de vazamento de credenciais de usuários e domínios com Have I Been Pwned.

**Fase 4 – maturidade**
- Gestão de exceções (risco aceito) com validade e responsável.
- Painel de métricas (dashboards no Wazuh ou Grafana).
- Teste de regressão: após correção, rodar o mesmo scan e confirmar fechamento.

## Pontos de atenção

- **Rate limits e custos das APIs**: VirusTotal, Shodan e Censys têm cotas no plano gratuito; cachear respostas no n8n ou em banco local e enriquecer apenas o que for necessário.
- **Escopo legal**: fazer scan ativo apenas em ativos próprios; o scan externo por Shodan/Censys é passivo, mas o Nuclei contra IPs de terceiros não deve ser usado.
- **Falsos positivos**: IA sugere, humano aprova. Não automatizar correções em produção sem janela e rollback.
- **Dados sensíveis**: não enviar a APIs externas hashes, nomes de usuários ou detalhes internos sem necessidade.
- **Ollama**: validar a qualidade do modelo com casos conhecidos antes de confiar na triagem.

## Fontes de dados mapeadas no projeto

ABUSEIPDB, GreyNoise, VirusTotal, Pulsedive, AlienVault OTX, Shodan, Censys, urlscan.io, MalwareBazaar, Hybrid Analysis, URLhaus, NVD NIST, GitHub API e Have I Been Pwned. As chaves ficam em `.env` (ver `.env.example`).
