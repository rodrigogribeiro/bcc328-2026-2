# BCC328 — Construção de Compiladores I

Repositório com o código-fonte dos exemplos, slides e notas de aula da
disciplina BCC328.

---

## Ferramentas disponíveis no ambiente

| Ferramenta | Versão | Uso |
|---|---|---|
| GHC | 9.6.7 | Compilador Haskell |
| Cabal | 3.12 | Gerenciador de pacotes e build |
| Alex | 3.5+ | Gerador de analisador léxico |
| Happy | 2.1+ | Gerador de analisador sintático (LALR) |
| RISC-V GCC | 11.4 | Cross-compilação para RISC-V 64 |
| Wasmtime | 25+ | Runtime WebAssembly |
| WABT | 1.0.34 | Ferramentas WebAssembly (wat2wasm, …) |
| LaTeX | TL 2023 | Compilação de slides e notas |

---

## Configurando o ambiente

Duas opções são suportadas: **Nix** (recomendado) ou **Docker Compose**.

---

### Opção 1 — Nix

**Pré-requisito:** Nix com suporte a flakes habilitado.

Para habilitar flakes, adicione ao arquivo `~/.config/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

**Entrando no ambiente:**

```bash
# Na raiz do repositório
nix develop
```

O comando acima baixa e configura automaticamente todas as ferramentas. Ao
entrar no shell, você verá a mensagem de boas-vindas com as versões instaladas.

Para compilar o projeto após entrar no shell:

```bash
cd workspace
cabal build
```

---

### Opção 2 — Docker Compose

**Pré-requisitos:** Docker Engine e Docker Compose v2+.

**Primeira execução** (constrói a imagem, pode demorar alguns minutos):

```bash
docker compose build
```

**Abrindo um shell de desenvolvimento:**

```bash
docker compose run --rm haskell-dev
```

Dentro do container, o código-fonte do workspace está em `/workspace`:

```bash
cd /workspace
cabal build
```

---

## Estrutura do projeto

```
.
├── workspace/          Código-fonte Haskell dos exemplos do curso
│   ├── src/
│   │   ├── Automata/       Algoritmos de autômatos (análise léxica)
│   │   ├── Exp/            Compilador de expressões → WASM e RISC-V
│   │   ├── Line/           Linguagem com atribuição, read e print
│   │   ├── While/          Linguagem imperativa simples
│   │   ├── TExp/           Expressões com verificação de tipos
│   │   ├── TLine/          Line com verificação de tipos
│   │   ├── TWhile/         While com verificação de tipos
│   │   ├── TImp/           Linguagem imperativa tipada (registros, funções)
│   │   ├── Lambda/         Cálculo lambda (avaliação e redução)
│   │   ├── MiniML/         Inferência de tipos (Hindley-Milner)
│   │   ├── FJ/             Featherweight Java
│   │   ├── IR/             Representação intermediária
│   │   ├── ClosureConvert/ Conversão de closures
│   │   ├── PEG/            Biblioteca de PEG parsing
│   │   └── Parsing/        CYK, LL(1) e LR parsing
│   └── test/           Testes automatizados (Tasty/HUnit)
├── slides/             Slides em LaTeX Beamer (um diretório por capítulo)
├── lecture-notes/      Notas de aula em LaTeX
└── assignments/        Especificações dos trabalhos práticos
```

---

## Executando os exemplos

Todos os executáveis são compilados com `cabal build` e executados com
`cabal run <nome>`. Passe `--help` para ver as opções de cada um.

```bash
cabal run exp      # Compilador de expressões (WASM + RISC-V)
cabal run line     # Compilador da linguagem Line
cabal run twhile   # Compilador While tipado
cabal run texp     # Compilador de expressões tipadas
cabal run tline    # Compilador Line tipado
cabal run timp     # Compilador TImp (registros e funções)
cabal run lambda   # Interpretador de cálculo lambda
cabal run mini-ml  # Inferência de tipos Mini ML
cabal run fj       # Interpretador Featherweight Java
cabal run ir       # Gerador de representação intermediária
```

Para executar os testes:

```bash
cabal test
```

---

## Compilando slides e notas de aula

Os slides de cada capítulo ficam em `slides/chapterNN/slides.tex`.
Para compilar um deck individualmente (dentro do ambiente Nix ou Docker):

```bash
cd slides/chapter09
pdflatex -shell-escape slides.tex
```

Para compilar todos os 28 decks de uma vez:

```bash
cd slides
bash compile-all.sh
```

As notas de aula ficam em `lecture-notes/`. Para compilar:

```bash
cd lecture-notes
latexmk -shell-escape -pdf main.tex
```
