# Recursos Cloudflare no Projeto Frank

## Recursos propostos

| Recurso | Uso no projeto | Custo esperado |
|---|---|---|
| Cloudflare Tunnel (cloudflared) | Publicar NPM, n8n e TheHive sem abrir portas no roteador | Incluído no plano gratuito |
| DNS | Zona do domínio, registros para o túnel | Incluído |
| Cloudflare Access (Zero Trust) | Login na frente de n8n, TheHive e Wazuh dashboard | Plano gratuito Zero Trust (até 50 usuários) |
| Gateway (DNS filtering) | Bloqueio de domínios maliciosos na rede interna/agentes | Plano gratuito Zero Trust (até 50 usuários), com limites de recursos |
| WAF (regras gerenciadas e customizadas) | Proteção básica dos sites publicados | Regras gerenciadas e quantidade de regras customizadas variam por plano |
| Certificados TLS | HTTPS nos domínios públicos | Incluído |

## O que pode gerar custo além do atual

Sinalizar antes de ativar:

- **Logpush** (envio de logs do Cloudflare para o Wazuh, S3 ou SIEM externo): normalmente exige plano Enterprise ou add-on pago, dependendo do dataset.
- **Mais de 50 usuários** no Zero Trust ou funções avançadas de DLP, CASB e Browser Isolation: planos pagos.
- **Regras WAF avançadas** e conjuntos gerenciados adicionais: depende do plano do domínio.
- **Argo Smart Routing, Load Balancing, Workers com alto volume** e Images: cobrados por uso.
- **Ultrapassar limites** de requisições do Workers ou de registros de Gateway, se o plano tiver cotas.

Antes de contratar qualquer add-on, verificar a página de preços vigente do Cloudflare e o painel de faturamento. Os limites de planos mudam com frequência, por isso não considerar as informações deste arquivo como definitivas.

## Passos de configuração (resumo)

1. No painel Zero Trust, criar um Tunnel do tipo Cloudflared e copiar o token para `CLOUDFLARE_TUNNEL_TOKEN` no `.env`.
2. Criar um Public Hostname para cada serviço apontando para o NPM (`http://npm:80`) ou diretamente para o serviço interno.
3. Criar uma Application no Access para `n8n.<domínio>`, `thehive.<domínio>` e `wazuh.<domínio>` com política de Allow restrita a e-mails autorizados.
4. Ativar a política de DNS do Gateway para bloqueio de malware e domínios de phishing (checar limites do plano antes).
5. Revisar o WAF no domínio com o modo "Managed rules" ativado.

## Observação

O painel administrativo do NPM fica apenas em `127.0.0.1:81` e acessível por SSH ou túnel. Não publicar a porta 81 na internet.
