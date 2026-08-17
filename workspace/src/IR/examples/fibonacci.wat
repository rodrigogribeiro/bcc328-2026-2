(module
   (import "env" "print" (func $print (param i32)))
   (import "env" "read_int" (func $read_int (result i32)))
   (memory 4)
   (global $heap_ptr (mut i32) (i32.const 0))
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
   (func $fib (param $n i32) (result i32)
      (local $a i32)
      (local $b i32)
      local.get $n
      i32.const 1
      i32.le_s
      (if
         (then
            local.get $n
            return))
      local.get $n
      i32.const 1
      i32.sub
      call $fib
      local.set $a
      local.get $n
      i32.const 2
      i32.sub
      call $fib
      local.set $b
      local.get $a
      local.get $b
      i32.add
      return
      unreachable)
   (func $main
      (local $result i32)
      i32.const 10
      call $fib
      local.set $result
      local.get $result
      call $print)
   (export "main" (func $main)))