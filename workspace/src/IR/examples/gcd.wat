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
   (func $gcd (param $a i32) (param $b i32) (result i32)
      (local $t i32)
      (block $done
         (loop $loop
            local.get $b
            i32.const 0
            i32.eq
            br_if $done
            local.get $a
            local.get $b
            i32.rem_s
            local.set $t
            local.get $b
            local.set $a
            local.get $t
            local.set $b
            br $loop))
      local.get $a
      return
      unreachable)
   (func $main
      (local $result i32)
      i32.const 48
      i32.const 18
      call $gcd
      local.set $result
      local.get $result
      call $print)
   (export "main" (func $main)))