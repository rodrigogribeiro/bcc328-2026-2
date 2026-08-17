---
title: "Transpilação: Geração de Código C"
subtitle: "BCC328 – Construção de Compiladores I"
---

# Objetivos

## Objetivos

- Apresentar o conceito de **transpilação** (_source-to-source compilation_) e
  sua importância na prática industrial.

- Estudar TypeScript como exemplo canônico de transpilador amplamente utilizado.

## Objetivos

- Implementar geradores de código C para TLine, TWhile e TImp, em ordem
  crescente de complexidade.

- Compreender a mônada de geração `CgM` e o padrão `withBlock` para controle de
  escopo léxico.

# Introdução

## O que é Transpilação?

- **Transpilação**: traduzir um programa de uma linguagem de alto nível para
  **outra linguagem de alto nível**, preservando a semântica.

## O que é Transpilação?

$$\text{AST tipada} \xrightarrow{\text{transpilador}} \text{Código C} \xrightarrow{\texttt{gcc}} \text{Binário}$$

- O transpilador **não gera código de máquina**: delega essa tarefa ao
  compilador da linguagem-alvo.

# Vantagens e Desvantagens

## Vantagens

- Portabilidade imediata para qualquer plataforma com o compilador-alvo
- Otimizações do compilador-alvo (`gcc -O2`) aplicadas automaticamente

## Vantagens

- Implementação mais simples: sem IRT, sem alocação de registradores
- Código gerado **legível** e depurável diretamente

## Desvantagens

- Controle limitado sobre a qualidade do código final
- Restrições da linguagem-alvo (expressividade, tipos disponíveis)

## Desvantagens

- _Encodings_ necessários para conceitos sem equivalente direto (ex.:
  `char[4096]` para strings de tamanho variável)

# TypeScript

## TypeScript

- **TypeScript** (Microsoft, 2012): adiciona um **sistema de tipos estático** ao
  JavaScript. O compilador `tsc` gera `.js` válido para qualquer ambiente.

## TypeScript

- Aspectos importantes:
  - **Tipos apagados em runtime** (_type erasure_): o `.js` gerado não contém
    nenhum rastro das anotações de tipo — segurança apenas em compile-time
  - **Compatibilidade**: ES2022 transpilado para ES5 quando necessário

## TypeScript

- Aspectos importantes:
  - **Escala industrial**: dezenas de milhões de desenvolvedores
  - **Source maps**: mapeiam posições no `.js` gerado de volta ao `.ts` original

# C como Linguagem-Alvo

## Por que C?

- C é uma escolha natural como alvo:
  - **Modelo de execução** simples: memória plana, controle estruturado, funções
  - **Biblioteca padrão**: `printf`/`scanf`, `malloc`, `strcpy`

## Por que C?

- **Portabilidade**: qualquer plataforma com `gcc` ou `clang`
- **Legibilidade**: o `.c` gerado pode ser inspecionado e depurado com `gdb`

## Por que C?

- Subconjunto de C utilizado:
  - Tipos: `long`, `int`, `char[N]`, `char *`, structs e ponteiros
  - Controle: `if`/`else`, `while`

## Por que C?

- Subonjunto de C utilizando:
  - Funções com `return` e `void`
  - `malloc`, `printf`, `scanf`, `fgets`, `strcpy`

## Mapeamento de Tipos

| Tipo fonte   | C (expressão) | C (variável local) |
| ------------ | ------------- | ------------------ |
| `int`        | `long`        | `long v`           |
| `bool`       | `int`         | `int v`            |
| `string`     | `char *`      | `char v[4096]`     |
| `R` (record) | `R *`         | `R *v`             |

## Mapeamento de Tipos

- **Por que `char[4096]` localmente?** `fgets` precisa de um buffer próprio.
  Parâmetros recebem `char *` (ponteiro para buffer existente).

## Mapeamento de Tipos

- **Por que `R *`?** Records são alocados dinamicamente com `malloc`: variáveis
  são sempre ponteiros.

## A Mônada de Geração `CgM`

```haskell
data CgSt = CgSt
  { cgLines  :: [String]   -- linhas de código C acumuladas
  , cgEnv    :: Map Var Ty -- tipos das variáveis em escopo
  , cgIndent :: Int        -- nível de indentação corrente
  }

type CgM a = StateT CgSt (ExceptT String Identity) a
```

## A Mônada de Geração `CgM`

- Operações primitivas:

```haskell
emit :: String -> CgM ()    -- emite uma linha com recuo corrente
indented :: CgM () -> CgM ()  -- aumenta/restaura nível de indentação
```

- `runCg :: CgM () -> Either String String` executa e coleta o código gerado.

# Geração de Código para TLine

## Estrutura do Código Gerado

Todo programa TLine → único arquivo C:

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    /* tradução dos comandos */
    return 0;
}
```

## Estrutura do Código Gerado

```haskell
compileTLine :: TLine -> Either String String
compileTLine (TLine stmts) = runCg $ do
  emit "#include <stdio.h>" >> emit "#include <stdlib.h>"
  emit "#include <string.h>" >> blank
  emit "int main(void) {"
  indented $ mapM_ genStmt stmts >> emit "return 0;"
  emit "}"
```

## Geração de Expressões

```haskell
genExp :: Map Var Ty -> Exp -> String
genExp _   (EInt n)      = show n ++ "L"   -- sufixo L → long
genExp _   (EBool True)  = "1"
genExp _   (EBool False) = "0"
genExp _   (EString s)   = "\"" ++ escapeC s ++ "\""
genExp _   (EVar v)      = v
genExp env (e1 :+: e2)   = parens (genExp env e1 ++ " + " 
                                ++ genExp env e2)
-- demais operadores: análogos
genExp env (Not e)        = "(!" ++ genExp env e ++ ")"
```

## Geração de Expressões

- **Decisões:**
  - `nL`: força `long` — evita truncamentos em 32 bits
  - `parens`: preserva precedência da AST independentemente do C
  - `escapeC`: escapa `"`, `\`, `\n` em strings literais

## Regras de Tradução de Expressões

$$\mathcal{E}_\Gamma\lbrack n \rbrack = \mathtt{nL} \qquad
\mathcal{E}_\Gamma\lbrack \mathbf{true} \rbrack = \mathtt{1} \qquad
\mathcal{E}_\Gamma\lbrack \mathbf{false} \rbrack = \mathtt{0}$$

$$\mathcal{E}_\Gamma\lbrack x \rbrack = x \qquad
\mathcal{E}_\Gamma\lbrack s \rbrack = \mathtt{"escapeC}(s)\mathtt{"}$$

$$\mathcal{E}_\Gamma\lbrack e_1 \oplus e_2 \rbrack =
  \mathtt{(}\mathcal{E}_\Gamma\lbrack e_1 \rbrack\ \mathit{opC}(\oplus)\ \mathcal{E}_\Gamma\lbrack e_2 \rbrack\mathtt{)}$$

$$\mathcal{E}_\Gamma\lbrack \mathbf{not}\ e \rbrack =
  \mathtt{(!}\mathcal{E}_\Gamma\lbrack e \rbrack\mathtt{)}$$

## Geração de Declaração

- **`SDecl v t e`: strings exigem tratamento especial:**

```haskell
genStmt (SDecl v t e) = do
  env <- gets cgEnv
  case t of
    TString -> emit ("char " ++ v ++ "[4096];")
            >> emit ("strcpy(" ++ v ++ ", " ++ genExp env e ++ ");")
    _       -> emit (cTy t ++ " " ++ v ++ " = " ++ genExp env e ++ ";")
  setVar v t
```

## Geração de Atribuição

- **`SAssign v e`: `strcpy` para strings:**

```haskell
genStmt (SAssign v e) = do
  ty <- getVarTy v
  case ty of
    TString -> 
        emit ("strcpy(" ++ v ++ ", " ++ genExp env e ++ ");")
    _       -> emit (v ++ " = " ++ genExp env e ++ ";")
```

## Geração de Print

- **`SPrint e`: formato escolhido pelo tipo de `e`:**

```haskell
case inferTy env e of
  TInt -> 
    emit ("printf(\"%ld\\n\", (long)(" ++ ce ++ "));")
  TBool -> 
    emit ("printf(\"%s\\n\", (" ++ ce ++ ") ? \"true\" : \"false\");")
  TString -> emit ("printf(\"%s\\n\", " ++ ce ++ ");")
```

## Geração de Read

- **`SRead prompt v`: prompt + leitura por tipo:**

```haskell
emit ("printf(\"%s\", " ++ genExp env prompt ++ ");")
case ty of
  TInt    -> emit ("scanf(\"%ld\", &" ++ v ++ ");")
  TString -> emit ("fgets(" ++ v ++ ", 4096, stdin);")
          >> emit (v ++ "[strcspn(" ++ v ++ ", \"\\n\")] = '\\0';")
```

## Exemplo Completo

Entrada:

```text
var a : int = 0;
var b : int = 0;
read "a: " a;
read "b: " b;
print a + b;
```

## Exemplo Completo

Saída:

```c
int main(void) {
    long a = 0L;
    long b = 0L;
    printf("%s", "a: ");
    scanf("%ld", &a);
    printf("%s", "b: ");
    scanf("%ld", &b);
    printf("%ld\n", (long)((a + b)));
    return 0;
}
```

# Geração de Código para TWhile

## Extensões em TWhile

- TWhile acrescenta sobre TLine:
  - `SWhile e body`: laço `while`
  - `SIf e b1 b2`: condicional `if`/`else`
  - Operadores `&&` e `||`

- Desafio principal: **escopo léxico** de variáveis em blocos.

## Escopo

- Em C (e em TWhile), variáveis declaradas dentro de `while`/`if` não são
  visíveis fora:

```c
while (cond) {
    long x = 5L;   // x só existe aqui
}
// x não existe aqui
```

## Escopo

- O código C gerado já respeita isso com `{ }`.

- **Mas**: `cgEnv` é estado global da mônada: sem restauração, uma variável
  declarada dentro de um bloco "vazaria" para o ambiente de geração posterior.

## A Solução: `withBlock`

```haskell
withBlock :: CgM () -> CgM ()
withBlock m = do
  saved <- gets cgEnv -- salva ambiente
  m -- executa geração do bloco
  modify $ \s -> s { cgEnv = saved } -- restaura
```

## Geração de `while`

```haskell
genStmt (SWhile e body) = do
  env <- gets cgEnv
  emit ("while (" ++ genExp env e ++ ") {")
  withBlock $ indented (mapM_ genStmt body)
  emit "}"
```

## Geração de `if`/`else`

```haskell
genStmt (SIf e b1 b2) = do
  env <- gets cgEnv
  emit ("if (" ++ genExp env e ++ ") {")
  withBlock $ indented (mapM_ genStmt b1)
  emit "} else {"
  withBlock $ indented (mapM_ genStmt b2)
  emit "}"
```

## Exemplo Completo

Entrada:

```text
var n : int = 5;
var acc : int = 1;
while n > 0 {
    acc := acc * n;
    n := n - 1;
}
print acc;
```

## Exemplo Completo

Saída:

```c
long n = 5L;
long acc = 1L;
while ((n > 0L)) {
    acc = (acc * n);
    n = (n - 1L);
}
printf("%ld\n", (long)(acc));
```

# Geração de Código para TImp

## Extensões

TImp acrescenta sobre TWhile:

- **Records**: `record R { f1 : t1; f2 : t2; }` — tipos produto nomeados
- **Funções de usuário** com recursão mútua
- **`f(args)`** — chamada como expressão ou statement

## Extensões

- **`return`** — retorno de função
- **`new R { ... }`** — alocação de record
- **`e.f`** — acesso a campo

## Estado para TImp

```haskell
data CgSt = CgSt
  { cgLines  :: [String]
  , cgIndent :: Int
  , cgEnv    :: Map Var Ty           -- variáveis em escopo
  , cgRecEnv :: Map Name [FieldDecl] -- campos de cada record
  , cgFnEnv  :: Map Name RetTy       -- retorno de cada função
  }
```

## Estado para TImp

- `cgRecEnv`: necessário para gerar `ENew` na ordem dos campos e para `inferTy`
  em `EField`
- `cgFnEnv`: necessário para `inferTy` em chamadas de função usadas dentro de
  `print`

## Records

Cada `record R { f1 : T1; f2 : T2; }` gera:

**1. Typedef struct:**

```c
typedef struct {
    long f1;
    long f2;
} R;
```

## Records

**2. Função construtora `make_R`:**

```c
R* make_R(long f1, long f2) {
    R* _r = (R*)malloc(sizeof(R));
    _r->f1 = f1;
    _r->f2 = f2;
    return _r;
}
```

## Por que `make_R`?

- `new R { x = 3, y = 4 }` precisa ser uma **expressão** C pura:
  - Pode aparecer em posição de argumento
  - Pode aparecer em inicializador de variável

## Por que `make_R`?

- Sem `make_R`, seria necessário _statement-expressions_ (extensão GCC):

```c
// NÃO portável:
Point *p = ({ Point *_r = malloc(sizeof(Point)); _r->x = 3; _r; });
```

## Por que `make_R`?

- Com `make_R`:

```c
// Portável, legível:
Point *p = make_Point(3L, 4L);
```

- `ENew` compila para uma chamada de função pura -> sem extensões.

## Expressões Adicionais de TImp

$$\mathcal{E}\lbrack x.f \rbrack = x\to f$$

$$\mathcal{E}\lbrack e.f \rbrack = \mathtt{(}\mathcal{E}\lbrack e\rbrack\mathtt{)}\to f$$

$$\mathcal{E}\lbrack f(\vec{e}) \rbrack = f\mathtt{(}\mathcal{E}\lbrack \vec{e}\rbrack\mathtt{)}$$

$$\mathcal{E}\lbrack \mathbf{new}\ R\ \{f_1 = e_1,\ldots\} \rbrack = \mathtt{make\_}R\mathtt{(}\mathcal{E}\lbrack e_{\sigma(1)}\rbrack\mathtt{,\ldots)}$$

onde $\sigma$ reordena campos conforme a **declaração** de $R$.

## Recursão Mútua

- TImp permite funções mutuamente recursivas:

```text
fn even(n: int): bool { return if n == 0 then true else odd(n-1); }
fn odd(n: int): bool  { return if n == 0 then false else even(n-1); }
```

## Recursão Mútua

- Em C, uma função deve ser declarada antes de ser chamada.
  - **Solução**: emitir _forward declarations_ de **todas** as funções antes de
    qualquer definição:

```c
int even(long n);   // forward declaration
int odd(long n);    // forward declaration

int even(long n) { ... }   // definição completa
int odd(long n)  { ... }   // definição completa
```

## Estrutura do Código Gerado para TImp

- Ordem de emissão:
  1. `#include` (cabeçalhos)
  2. `typedef struct { ... } R;` para cada record

## Estrutura do Código Gerado para TImp

- Ordem de emissão: 3. `R* make_R(...)` para cada record 4. Forward declarations
  de todas as funções

## Estrutura do Código Gerado para TImp

- Ordem de emissão: 5. Definições completas de todas as funções 6.
  `int main(void) { ... }` com os statements de topo

## Exemplo

Entrada:

```text
record Point { x : int; y : int; }
fn distance(p: Point): int {
    return p.x * p.x + p.y * p.y;
}
var p : Point = new Point { x = 3, y = 4 };
print distance(p);
```

## Exemplo

Saída (estrutura):

```c
typedef struct { long x; long y; } Point;
Point* make_Point(long x, long y) { ... }
long distance(Point * p);
long distance(Point * p) {
    return ((p->x * p->x) + (p->y * p->y));
}
int main(void) {
    Point *p = make_Point(3L, 4L);
    printf("%ld\n", (long)(distance(p)));
    return 0;
}
```

# Conclusão

## Conclusão

- Apresentamos a técnica de transpilação para geração de código.
- Estruturamos a implementação em termos de uma mônada.
  - Organizamos a geração de código para satisfazer as restrições de C.
