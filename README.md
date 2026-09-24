# Gerenciador AD

Aplicativo administrativo em PowerShell 5.1 + Windows Forms para operações do dia a dia no Active Directory (RSAT).

> **Versão "limpa":** este repositório não contém nenhuma referência a uma organização específica. Todos os valores (empresa, escritórios, departamentos, cargos, setores, domínio de e-mail e OUs) são configuráveis em tempo de execução e ficam salvos em um arquivo `padroes.json`.

## Funcionalidades

- **Cadastro / padronização de usuários** — crie um novo usuário ou busque um existente e padronize os dados conforme os valores padronizados (descrição no formato `SETOR - Ticket NUMERO`, com suporte a cobertura: `SETOR - Final da Cobertura DATA - Ticket NUMERO`).
- **Reset / desbloqueio de senha** — gera senha temporária, desbloqueia e redefine a conta.
- **Consultar acessos** — nome, e-mail e grupos dos quais o usuário é membro.
- **Gerenciar grupos** — consulta, adiciona, remove, copia (espelha) e compara grupos entre usuários.
- **Desativar usuário** — desativa a conta, registra histórico, remove grupos e move para a OU de desativados.
- **Mover máquinas para OU** — valida e move computadores informados em lote (aceita caminho amigável ou DN).
- **Gerar relatório** — por cargo, cobertura, desativados, ativos e inativos há mais de 90 dias.
- **Histórico do usuário** — visualiza o atributo `info` (observações) do AD.
- **Alteração em massa** — padroniza cargo, departamento, escritório e empresa de vários usuários de uma vez.
- **Central de inconsistências** — auditoria somente leitura que identifica cadastros incompletos e máquinas fora da OU padrão, com exportação para CSV.

## Requisitos

- Windows com **PowerShell 5.1** (nativo em Windows 10/11)
- **RSAT** com o módulo `ActiveDirectory` instalado
- Credencial administrativa válida no domínio (é solicitada uma única vez no login e mantida apenas em memória)

## Como executar

```
powershell -ExecutionPolicy Bypass -File Gerenciador-AD-Limpo.ps1
```

Ao abrir, informe no login o usuário administrativo no formato `dominio\administrador`.

## Configuração inicial (primeiro uso)

No primeiro uso, o aplicativo cria o arquivo de padrões em:

```
%APPDATA%\Gerenciador-AD\padroes.json
```

Os valores de exemplo (`EMPRESA`, `ESCRITORIO`, `DEPARTAMENTO`, `CARGO`, `SETOR`, `dominio.com.br`, etc.) devem ser ajustados conforme a sua organização. Você pode configurar pela tela **Valores padronizados** do próprio aplicativo, ou editando o JSON diretamente.

### Campos do `padroes.json`

| Chave            | Descrição                                                              | Exemplo                                     |
|------------------|------------------------------------------------------------------------|---------------------------------------------|
| `Empresas`       | Lista de empresas aceitas no cadastro                                  | `["MINHA-EMPRESA"]`                          |
| `Escritorios`    | Lista de escritórios/unidades                                          | `["MATRIZ"]`                                 |
| `Departamentos`  | Lista de departamentos                                                 | `["TI", "FINANCEIRO"]`                       |
| `Cargos`         | Lista de cargos                                                        | `["Analista", "Coordenador"]`                |
| `Setores`        | Lista de setores usados na descrição (`SETOR - Ticket ...`)            | `["TI", "RH"]`                               |
| `EmailDominio`   | Sufixo de e-mail para criar UPN/e-mail automaticamente                 | `"minhaempresa.com.br"`                      |
| `OUUsuarios`     | OU (DN) onde novos usuários são criados                                | `"OU=USUARIOS,DC=minhaempresa,DC=com,DC=br"` |

> A OU de desativados é derivada automaticamente de `OUUsuarios` (substitui a primeira `OU=` por `OU=DESATIVADOS`). Crie essa OU no domínio se for utilizada.

## Caminhos amigáveis vs. DN

Em telas como **Mover máquinas** e **Central de inconsistências** você pode informar:

- **Caminho amigável:** `dominio.com.br/WORKSTATIONS/OU_DESTINO/` (o domínio é convertido em `DC=` automaticamente: `OU=OU_DESTINO,OU=WORKSTATIONS,DC=dominio,DC=com,DC=br`)
- **DN do Active Directory:** `OU=OU_DESTINO,OU=WORKSTATIONS,DC=dominio,DC=com,DC=br`

## Segurança

- A credencial administrativa é solicitada **uma vez** por sessão e permanece **somente em memória**.
- Ao fechar o aplicativo a referência da credencial é descartada.
- As operações destrutivas (desativar, remover grupo, mover/alterar em massa) exigem confirmação explícita.

## Observações

- Textos das telas são exibidos sem acentos para evitar conflitos de encoding no console Windows.
- O histórico de alterações é gravado no atributo `info` do usuário no AD.