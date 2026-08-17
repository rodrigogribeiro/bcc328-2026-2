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
   (func $factorial (param $n i32) (result i32)
      (local $acc i32)
      i32.const 1
      local.set $acc
      (block $done
         (loop $loop
            local.get $n
            i32.const 0
            i32.le_s
            br_if $done
            local.get $acc
            local.get $n
            i32.mul
            local.set $acc
            local.get $n
            i32.const 1
            i32.sub
            local.set $n
            br $loop))
      local.get $acc
      return
      unreachable)
   (func $main
      (local $result i32)
      i32.const 5
      call $factorial
      local.set $result
      local.get $result
      call $print)
   (export "main" (func $main)))