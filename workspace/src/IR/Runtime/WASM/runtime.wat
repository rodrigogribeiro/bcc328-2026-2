(module
  ;; WASI imports for I/O
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read"  (func $fd_read  (param i32 i32 i32 i32) (result i32)))

  ;; Memory shared with the compiled program (must match the 4-page declaration
  ;; in the generated module when linked together).
  ;; Memory layout for I/O buffers (low addresses, below any heap use):
  ;;   0–15  : iovec structure (ptr at 0, len at 4)
  ;;  16–31  : nwritten / nread return slot
  ;;  32–63  : input  buffer (32 bytes)
  ;;  64–95  : output buffer (32 bytes)
  (memory (export "memory") 1)

  ;; print(value : i32) -> void
  ;; Converts an i32 to its decimal representation and writes it to stdout
  ;; followed by a newline.  Exported as "print" to match the IR import name.
  (func $print (export "print") (param $value i32)
    (local $temp  i32)
    (local $digit i32)
    (local $len   i32)
    (local $neg   i32)
    (local $pos   i32)

    ;; ── sign handling ──────────────────────────────────────────────────────
    local.get $value
    i32.const 0
    i32.lt_s
    local.set $neg

    local.get $value
    local.get $neg
    if (result i32)
      i32.const 0
      local.get $value
      i32.sub
    else
      local.get $value
    end
    local.set $temp

    ;; ── build decimal string in reverse into output buffer (64–95) ─────────
    i32.const 95
    local.set $pos

    local.get $temp
    i32.eqz
    if
      ;; special-case zero
      local.get $pos
      i32.const 48
      i32.store8
      local.get $pos
      i32.const 1
      i32.sub
      local.set $pos
      i32.const 1
      local.set $len
    else
      loop $digit_loop
        local.get $temp
        i32.eqz
        br_if $digit_loop

        local.get $temp
        i32.const 10
        i32.rem_u
        i32.const 48
        i32.add
        local.set $digit

        local.get $pos
        local.get $digit
        i32.store8

        local.get $pos
        i32.const 1
        i32.sub
        local.set $pos

        local.get $temp
        i32.const 10
        i32.div_u
        local.set $temp

        local.get $len
        i32.const 1
        i32.add
        local.set $len

        br $digit_loop
      end
    end

    ;; ── prepend '-' if negative ────────────────────────────────────────────
    local.get $neg
    if
      local.get $pos
      i32.const 45
      i32.store8
      local.get $pos
      i32.const 1
      i32.sub
      local.set $pos
      local.get $len
      i32.const 1
      i32.add
      local.set $len
    end

    ;; ── append newline ─────────────────────────────────────────────────────
    ;; Reuse the byte just after the number string.
    ;; The string starts at pos+1 and is $len bytes long;
    ;; the newline goes at pos+1+len.
    local.get $pos
    i32.const 1
    i32.add
    local.get $len
    i32.add
    i32.const 10       ;; '\n'
    i32.store8
    local.get $len
    i32.const 1
    i32.add
    local.set $len

    ;; ── iovec: ptr = pos+1, len = $len ────────────────────────────────────
    i32.const 0
    local.get $pos
    i32.const 1
    i32.add
    i32.store

    i32.const 4
    local.get $len
    i32.store

    ;; ── fd_write(stdout=1, iovs=0, iovs_len=1, nwritten=16) ───────────────
    i32.const 1
    i32.const 0
    i32.const 1
    i32.const 16
    call $fd_write
    drop
    drop
  )

  ;; read_int() -> i32
  ;; Reads a line from stdin and parses it as a signed decimal integer.
  (func $read_int (export "read_int") (result i32)
    (local $bytes_read i32)
    (local $result     i32)
    (local $pos        i32)
    (local $char       i32)
    (local $neg        i32)

    ;; ── read stdin into buffer at 32 ──────────────────────────────────────
    i32.const 0
    i32.const 32
    i32.store

    i32.const 4
    i32.const 31
    i32.store

    i32.const 0
    i32.const 0
    i32.const 1
    i32.const 16
    call $fd_read
    drop

    i32.const 16
    i32.load
    local.set $bytes_read

    ;; ── parse ─────────────────────────────────────────────────────────────
    i32.const 32
    local.set $pos

    local.get $pos
    i32.load8_u
    i32.const 45
    i32.eq
    if
      i32.const 1
      local.set $neg
      local.get $pos
      i32.const 1
      i32.add
      local.set $pos
    end

    loop $parse_loop
      local.get $pos
      i32.load8_u
      local.set $char

      local.get $char
      i32.const 48
      i32.ge_u
      local.get $char
      i32.const 57
      i32.le_u
      i32.and
      if
        local.get $result
        i32.const 10
        i32.mul
        local.get $char
        i32.const 48
        i32.sub
        i32.add
        local.set $result

        local.get $pos
        i32.const 1
        i32.add
        local.set $pos

        br $parse_loop
      end
    end

    local.get $neg
    if (result i32)
      i32.const 0
      local.get $result
      i32.sub
    else
      local.get $result
    end
  )
)
