# Compila arquivos .timp para .wasm em três passos:
#   .timp → .ir  (cabal run timp)
#   .ir   → .wat (cabal run ir)
#   .wat  → .wasm (wat2wasm)
#
# Uso:
#   make examples/factorial.wasm   # compila um arquivo específico
#   make all                       # compila todos os .timp em examples/
#   make run FILE=examples/factorial.wasm  # executa com wasmtime
#   make clean                     # remove artefatos gerados

WORKSPACE := $(realpath ../..)
CABAL     := cabal
WAT2WASM  := wat2wasm
WASMTIME  := wasmtime

TIMP_SRCS := $(wildcard examples/*.timp)
WASM_BINS := $(TIMP_SRCS:.timp=.wasm)

# Preserva arquivos intermediários (.ir e .wat) para inspeção
.PRECIOUS: %.ir %.wat

.PHONY: all run clean

all: $(WASM_BINS)

# Regra principal: .timp → .ir → .wat → .wasm
%.wasm: %.wat
	$(WAT2WASM) $< -o $@

%.wat: %.ir
	cd $(WORKSPACE) && $(CABAL) run -v0 ir -- --wat $(CURDIR)/$<

%.ir: %.timp
	cd $(WORKSPACE) && $(CABAL) run -v0 timp -- --ir -f $(CURDIR)/$<

# Executa um .wasm com wasmtime (uso: make run FILE=examples/factorial.wasm)
run: $(FILE)
	$(WASMTIME) $(FILE)

clean:
	rm -f examples/*.ir examples/*.wat examples/*.wasm
