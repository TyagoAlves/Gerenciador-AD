# Gerenciador AD

Aplicativo administrativo em PowerShell 5.1 + Windows Forms para operações do dia a dia no Active Directory (RSAT).

> **Versão "limpa":** este repositório não contém nenhuma referência a uma organização específica. Todos os valores (empresa, escritórios, departamentos, cargos, setores, domínio de e-mail e OUs) são configuráveis em tempo de execução e ficam salvos em um arquivo `padroes.json`.

---

## 🚀 Funcionalidades

- **Cadastro / padronização de usuários** — crie um novo usuário ou busque um existente e padronize os dados conforme os valores padronizados (descrição no formato `SETOR - Ticket NUMERO`, com suporte a cobertura: `SETOR - Final da Cobertura DATA - Ticket NUMERO`).
- **Reset / desbloqueio de senha** — gera senha temporária, desbloqueia e redefine a conta, forçando a troca no próximo logon.
- **Consultar acessos** — exibe nome, e-mail e lista de grupos dos quais o usuário é membro.
- **Gerenciar grupos** — consulta, adiciona, remove, copia (espelha) e compara grupos entre usuários.
- **Desativar usuário** — desativa a conta, registra histórico, remove grupos de permissão e move o objeto para a OU de desativados.
- **Mover máquinas para OU** — valida e move computadores informados em lote (aceita caminho amigável ou DN).
- **Gerar relatório** — relatórios estruturados por cargo, cobertura, desativados, ativos e inativos há mais de 90 dias.
- **Histórico do usuário** — visualiza o atributo `info` (observações) do AD mantendo rastreabilidade total.
- **Alteração em massa** — padroniza cargo, departamento, escritório e empresa de vários usuários selecionados simultaneamente.
- **Central de inconsistências** — auditoria somente leitura que identifica cadastros incompletos e máquinas fora da OU padrão, com exportação para CSV.

---

## 📋 Requisitos do Sistema

- Windows com **PowerShell 5.1** (nativo em Windows 10/11 / Windows Server).
- **RSAT** com o módulo `ActiveDirectory` instalado.
- Credencial administrativa válida no domínio.

---

## 🔐 Segurança

- **Login Único**: A credencial administrativa é solicitada **uma única vez** no login e mantida **somente em memória** durante a execução.
- Ao fechar o aplicativo, a referência da credencial é descartada de forma segura.
- Operações críticas e destrutivas (como desativar contas, remoção de grupos ou alterações em massa) exigem confirmação explícita do operador.

---

## ⚙️ Como Executar

No terminal PowerShell com permissões adequadas, execute:

```powershell
powershell -ExecutionPolicy Bypass -File Gerenciador-AD-Limpo.ps1
```

Ao abrir, informe no painel de login o seu usuário administrativo no formato `dominio\administrador`.

---

## 🛠️ Configuração Inicial (Primeiro Uso)

No primeiro uso, o aplicativo cria automaticamente o arquivo de parâmetros locais em:

```text
%APPDATA%\Gerenciador-AD\padroes.json
```

Os valores de exemplo devem ser ajustados conforme a estrutura da sua organização. Você pode editá-los diretamente pelo menu **Valores padronizados** na interface gráfica do aplicativo ou alterando o arquivo JSON.

### Campos do `padroes.json`

| Chave | Descrição | Exemplo |
| :--- | :--- | :--- |
| `Empresas` | Lista de empresas aceitas no cadastro | `["MINHA-EMPRESA"]` |
| `Escritorios` | Lista de escritórios / unidades | `["MATRIZ"]` |
| `Departamentos` | Lista de departamentos corporativos | `["TI", "FINANCEIRO"]` |
| `Cargos` | Lista de cargos válidos | `["Analista", "Coordenador"]` |
| `Setores` | Setores usados na descrição (`SETOR - Ticket ...`) | `["TI", "RH"]` |
| `EmailDominio` | Sufixo de e-mail para geração de UPN e e-mail | `"minhaempresa.com.br"` |
| `OUUsuarios` | Caminho DN da OU onde novos usuários são criados | `"OU=USUARIOS,DC=minhaempresa,DC=com,DC=br"` |

> *Nota:* A OU de desativados é derivada automaticamente a partir de `OUUsuarios` (substituindo a primeira ocorrência de `OU=` por `OU=DESATIVADOS`). Certifique-se de criar essa OU no seu domínio se for utilizá-la.

---

## 📂 Caminhos Amigáveis vs. DN

Em módulos como **Mover máquinas** e **Central de inconsistências**, você pode informar os caminhos de duas formas:

1. **Caminho amigável:** `dominio.com.br/WORKSTATIONS/OU_DESTINO/` (o aplicativo converte automaticamente em `DC=` e `OU=` no formato padrão do Active Directory).
2. **DN do Active Directory:** `OU=OU_DESTINO,OU=WORKSTATIONS,DC=dominio,DC=com,DC=br`.

---

## 📝 Observações

- Os textos das interfaces foram otimizados para exibição correta no console Windows.
- O histórico detalhado de alterações efetuadas pelo painel é gravado automaticamente no atributo `info` do objeto no Active Directory.

## 📄 Licença

Este projeto é de uso interno e livre para adaptações em ambientes corporativos de infraestrutura de TI.
