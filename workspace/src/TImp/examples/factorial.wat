(module
   (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32) (param i32) (param i32) (param i32) (result i32)))
   (import "wasi_snapshot_preview1" "fd_read" (func $fd_read (param i32) (param i32) (param i32) (param i32) (result i32)))
   (memory (export "memory") 4)
   (global $heap_ptr (mut i32) (i32.const 128))
   (func $alloc (param $n i32) (result i32)
      (local $base i32)
      global.get $heap_ptr
      local.set $base
      global.get $heap_ptr
      local.get $n
      i32.const 8
      i32.mul
      i32.add
      global.set $heap_ptr
      local.get $base)
   (func $factorial (param $n i32) (result i32)
      local.get $n
      i32.const 0
      i32.eq
      (if
         (then
            i32.const 1
            return)
         (else
            local.get $n
            local.get $n
            i32.const 1
            i32.sub
            call $factorial
            i32.mul
            return))
      unreachable)
   (func $factorialIter (param $n i32) (result i32)
      (local $i i32)
      (local $result i32)
      i32.const 1
      local.set $result
      local.get $n
      local.set $i
      (block $while_exit_2
         (loop $while_head_0
            local.get $i
            i32.const 0
            i32.gt_s
            i32.eqz
            br_if $while_exit_2
            local.get $result
            local.get $i
            i32.mul
            local.set $result
            local.get $i
            i32.const 1
            i32.sub
            local.set $i
            br $while_head_0))
      local.get $result
      return
      unreachable)
   (func $main
      (local $n i32)
      i32.const 0
      local.set $n
      call $read_int
      local.set $n
      local.get $n
      call $factorial
      call $print
      local.get $n
      call $factorialIter
      call $print)
   (export "main" (func $main))
   (export "_start" (func $main))
     (func $print (param $value i32)
    (local $temp  i32)
    (local $digit i32)
    (local $len   i32)
    (local $neg   i32)
    (local $pos   i32)
    local.get $value
    i32.const 0
    i32.lt_s
    local.set $neg
    local.get $neg
    if
      i32.const 0
      local.get $value
      i32.sub
      local.set $temp
    else
      local.get $value
      local.set $temp
    end
    i32.const 95
    local.set $pos
    local.get $temp
    i32.eqz
    if
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
      block $done
        loop $digit_loop
          local.get $temp
          i32.eqz
          br_if $done
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
    end
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
    local.get $pos
    i32.const 1
    i32.add
    local.get $len
    i32.add
    i32.const 10
    i32.store8
    local.get $len
    i32.const 1
    i32.add
    local.set $len
    i32.const 0
    local.get $pos
    i32.const 1
    i32.add
    i32.store
    i32.const 4
    local.get $len
    i32.store
    i32.const 1
    i32.const 0
    i32.const 1
    i32.const 16
    call $fd_write
    drop)

     (func $read_int (result i32)
    (local $result i32)
    (local $pos    i32)
    (local $char   i32)
    (local $neg    i32)
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
    block $done
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
        i32.eqz
        br_if $done
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
    if
      i32.const 0
      local.get $result
      i32.sub
      return
    end
    local.get $result)
)