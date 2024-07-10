requires "evm.md"
requires "foundry.md"

module LIDO-LEMMAS
    imports EVM
    imports FOUNDRY
    imports INT-SYMBOLIC
    imports MAP-SYMBOLIC
    imports SET-SYMBOLIC

    syntax StepSort ::= Int
                      | Bool
                      | Bytes
                      | Map
                      | Set
 // -------------------------

    syntax KItem ::= runLemma ( StepSort )
                   | doneLemma( StepSort )
 // --------------------------------------
    rule <k> runLemma(T) => doneLemma(T) ... </k>

    syntax Int ::= "ethMaxWidth" [macro]
    syntax Int ::= "ethUpperBound" [macro]
 // --------------------------------------
    rule ethMaxWidth => 96
    rule ethUpperBound => 2 ^Int ethMaxWidth
 // ----------------------------------------

    // /Int to byte representation
    rule X /Int pow160 => #asWord ( #range ( #buf ( 32 , X ) , 0 , 12 ) )
      requires #rangeUInt(256, X)
      [simplification, preserves-definedness]

    // Deconstruction of mask
    rule 115792089237316195423570984636004990333889740523700931696805413995650331181055 &Int X =>
            #asWord ( #range(#buf(32, X), 0, 11) +Bytes #buf(1, 0) +Bytes #range(#buf(32, X), 12, 20) )
      requires #rangeUInt(256, X)
      [simplification]

    // |Int distributivity over #asWord and +Bytes, v1
    rule A |Int #asWord ( BA1 +Bytes BA2 ) =>
      #asWord ( BA1 +Bytes #buf ( lengthBytes(BA2), A |Int #asWord ( BA2 ) ) )
      requires 0 <=Int A andBool A <Int 2 ^Int (8 *Int lengthBytes(BA2))
      [concrete(A), simplification]

    // |Int distributivity over #asWord and +Bytes, v2
    rule A |Int #asWord ( BA1 +Bytes BA2 ) =>
      #asWord (
        #buf ( lengthBytes(BA1), (A >>Int (8 *Int lengthBytes(BA2))) |Int #asWord ( BA1 ) )
        +Bytes
        #buf ( lengthBytes(BA2), (A modInt (2 ^Int (8 *Int lengthBytes(BA2)))) |Int #asWord ( BA2 ) )
      )
      requires #rangeUInt(256, A)
      [simplification, concrete(A, BA1)]

    // |Int and #asWord
    rule #range ( #buf ( A, X |Int Y) , 0, B ) =>
      #buf ( B, X >>Int (8 *Int (A -Int B)) )
      requires B <=Int A
       andBool 0 <=Int X andBool X <Int 2 ^Int (8 *Int A)
       andBool 0 <=Int Y andBool Y <Int 2 ^Int (8 *Int (A -Int B))
      [simplification, concrete(A, B)]

    // chop and -Int
    rule chop (A +Int B) ==Int 0 => A ==Int (-1) *Int B
      requires #rangeUInt(256, A) andBool #rangeUInt(256, (-1) *Int B)
      [concrete(B), simplification, comm]

    rule chop (0 -Int A) ==Int B => A ==Int (pow256 -Int B) modInt pow256
      requires #rangeUInt(256, A) andBool #rangeUInt(256, B)
      [concrete(B), simplification, comm]

    // *Int
    rule A *Int B ==Int 0 => A ==Int 0 orBool B ==Int 0 [simplification]

    // /Int
    rule 0 /Int B         => 0         requires B =/=Int 0 [simplification, preserves-definedness]
    rule A /Int B ==Int 0 => A ==Int 0 requires B =/=Int 0 [simplification, preserves-definedness]

    // /Word
    rule  _ /Word W1 => 0          requires W1  ==Int 0 [simplification]
    rule W0 /Word W1 => W0 /Int W1 requires W1 =/=Int 0 [simplification, preserves-definedness]

    // Further arithmetic
    rule ( X *Int Y ) /Int Y => X requires Y =/=Int 0              [simplification, preserves-definedness]
    rule ( X ==Int ( X *Int Y ) /Word Y ) orBool Y ==Int 0 => true [simplification, preserves-definedness]
    rule ( 0 ==Int          0   /Word Y ) orBool Y ==Int 0 => true [simplification, preserves-definedness]

    rule A <=Int B /Int C =>         A  *Int C <=Int B requires 0 <Int C [simplification, preserves-definedness]
    rule A  <Int B /Int C => (A +Int 1) *Int C <=Int B requires 0 <Int C [simplification, preserves-definedness]
    rule A  >Int B /Int C =>         A  *Int C  >Int B requires 0 <Int C [simplification, preserves-definedness]
    rule A >=Int B /Int C => (A +Int 1) *Int C  >Int B requires 0 <Int C [simplification, preserves-definedness]

    rule B /Int C >=Int A =>         A  *Int C <=Int B requires 0 <Int C [simplification, preserves-definedness]
    rule B /Int C  >Int A => (A +Int 1) *Int C <=Int B requires 0 <Int C [simplification, preserves-definedness]
    rule B /Int C  <Int A =>         A  *Int C  >Int B requires 0 <Int C [simplification, preserves-definedness]
    rule B /Int C <=Int A => (A +Int 1) *Int C  >Int B requires 0 <Int C [simplification, preserves-definedness]

    // Further generalization of: maxUIntXXX &Int #asWord ( BA )
    rule X &Int #asWord ( BA ) => #asWord ( #range(BA, lengthBytes(BA) -Int (log2Int(X +Int 1) /Int 8), log2Int(X +Int 1) /Int 8) )
    requires #rangeUInt(256, X)
     andBool X +Int 1 ==Int 2 ^Int log2Int(X +Int 1)
     andBool log2Int (X +Int 1) modInt 8 ==Int 0
     andBool (log2Int (X +Int 1)) /Int 8 <=Int lengthBytes(BA) andBool lengthBytes(BA) <=Int 32
     [simplification, concrete(X), preserves-definedness]

    // &Int distributivity
    rule X &Int ( Y |Int Z ) => ( X &Int Y ) |Int ( X &Int Z ) [simplification, concrete(X)]
    rule X &Int ( Y &Int Z ) => ( X &Int Y ) &Int ( X &Int Z ) [simplification, concrete(X)]

    // KEVM simplification
    rule #asWord(WS) >>Int M => #asWord(#range(WS, 0, lengthBytes(WS) -Int (M /Int 8) ))
    requires 0 <=Int M andBool M modInt 8 ==Int 0
    [simplification, preserves-definedness]

    //
    // .Bytes
    //
    rule .Bytes ==K b"" => true [simplification, comm]

    rule    b"" ==K #buf(X, _) +Bytes _ => false requires 0 <Int X [simplification, concrete(X), comm]
    rule    b"" ==K _ +Bytes #buf(X, _) => false requires 0 <Int X [simplification, concrete(X), comm]
    rule .Bytes ==K #buf(X, _) +Bytes _ => false requires 0 <Int X [simplification, concrete(X), comm]
    rule .Bytes ==K _ +Bytes #buf(X, _) => false requires 0 <Int X [simplification, concrete(X), comm]

    rule [concat-neutral-left]:  b"" +Bytes B:Bytes => B:Bytes [simplification]
    rule [concat-neutral-right]: B:Bytes +Bytes b"" => B:Bytes [simplification]

    //
    // Alternative memory update
    //
    rule [memUpdate-concat-in-right]: (B1 +Bytes B2) [ S := B ] => B1 +Bytes (B2 [ S -Int lengthBytes(B1) := B ])
      requires lengthBytes(B1) <=Int S
      [simplification(40)]

    rule [memUpdate-concat-in-left]: (B1 +Bytes B2) [ S := B ] => (B1 [S := B]) +Bytes B2
      requires 0 <=Int S andBool S +Int lengthBytes(B) <=Int lengthBytes(B1)
      [simplification(45)]

    //
    // Equality of +Bytes
    //
    rule { B:Bytes #Equals B1:Bytes +Bytes B2:Bytes } =>
           { #range ( B, 0, lengthBytes(B1) ) #Equals B1 } #And
           { #range ( B, lengthBytes(B1), lengthBytes(B) -Int lengthBytes(B1) ) #Equals B2 }
      requires lengthBytes(B1) <=Int lengthBytes(B)
      [simplification(60), concrete(B, B1)]

    rule { B1:Bytes +Bytes B2:Bytes #Equals B } =>
           { #range ( B, 0, lengthBytes(B1) ) #Equals B1 } #And
           { #range ( B, lengthBytes(B1), lengthBytes(B) -Int lengthBytes(B1) ) #Equals B2 }
      requires lengthBytes(B1) <=Int lengthBytes(B)
      [simplification(60), concrete(B, B1)]

    rule { B:Bytes #Equals #buf( N, X:Int ) +Bytes B2:Bytes } =>
           { X #Equals #asWord ( #range ( B, 0, N ) ) } #And
           { #range ( B, N, lengthBytes(B) -Int N ) #Equals B2 }
      requires N <=Int lengthBytes(B)
      [simplification(60), concrete(B, N)]

    rule { #buf( N, X:Int ) +Bytes B2:Bytes #Equals B } =>
           { X #Equals #asWord ( #range ( B, 0, N ) ) } #And
           { #range ( B, N, lengthBytes(B) -Int N ) #Equals B2 }
      requires N <=Int lengthBytes(B)
      [simplification(60), concrete(B, N)]

    //
    // Specific simplifications
    //
    rule X &Int #asWord ( BA ) ==Int Y:Int => true
    requires 0 <=Int X andBool X <Int 2 ^Int (8 *Int lengthBytes(BA))
     andBool X +Int 1 ==Int 2 ^Int log2Int(X +Int 1)
     andBool log2Int (X +Int 1) modInt 8 ==Int 0
     andBool #asWord ( #range(BA, lengthBytes(BA) -Int (log2Int(X +Int 1) /Int 8), log2Int(X +Int 1) /Int 8) ) ==Int Y:Int
     [simplification, concrete(X), comm, preserves-definedness]

    rule X &Int #asWord ( BA ) ==Int Y:Int => false
    requires 0 <=Int X andBool X <Int 2 ^Int (8 *Int lengthBytes(BA))
     andBool X +Int 1 ==Int 2 ^Int log2Int(X +Int 1)
     andBool log2Int (X +Int 1) modInt 8 ==Int 0
     andBool notBool #asWord ( #range(BA, lengthBytes(BA) -Int (log2Int(X +Int 1) /Int 8), log2Int(X +Int 1) /Int 8) ) ==Int Y:Int
     [simplification, concrete(X), comm, preserves-definedness]

    rule X &Int #asWord ( BA ) <Int Y:Int => true
    requires 0 <=Int X andBool X <Int 2 ^Int (8 *Int lengthBytes(BA))
     andBool X +Int 1 ==Int 2 ^Int log2Int(X +Int 1)
     andBool log2Int (X +Int 1) modInt 8 ==Int 0
     andBool #asWord ( #range(BA, lengthBytes(BA) -Int (log2Int(X +Int 1) /Int 8), log2Int(X +Int 1) /Int 8) ) <Int Y:Int
     [simplification, concrete(X), preserves-definedness]

    rule X &Int #asWord ( BA ) <Int Y:Int => false
    requires 0 <=Int X andBool X <Int 2 ^Int (8 *Int lengthBytes(BA))
     andBool X +Int 1 ==Int 2 ^Int log2Int(X +Int 1)
     andBool log2Int (X +Int 1) modInt 8 ==Int 0
     andBool notBool #asWord ( #range(BA, lengthBytes(BA) -Int (log2Int(X +Int 1) /Int 8), log2Int(X +Int 1) /Int 8) ) <Int Y:Int
     [simplification, concrete(X), preserves-definedness]

    rule X &Int #asWord ( BA ) <=Int Y:Int => true
    requires 0 <=Int X andBool X <Int 2 ^Int (8 *Int lengthBytes(BA))
     andBool X +Int 1 ==Int 2 ^Int log2Int(X +Int 1)
     andBool log2Int (X +Int 1) modInt 8 ==Int 0
     andBool #asWord ( #range(BA, lengthBytes(BA) -Int (log2Int(X +Int 1) /Int 8), log2Int(X +Int 1) /Int 8) ) <=Int Y:Int
     [simplification, concrete(X), preserves-definedness]

    rule X &Int #asWord ( BA ) <=Int Y:Int => false
    requires 0 <=Int X andBool X <Int 2 ^Int (8 *Int lengthBytes(BA))
     andBool X +Int 1 ==Int 2 ^Int log2Int(X +Int 1)
     andBool log2Int (X +Int 1) modInt 8 ==Int 0
     andBool notBool #asWord ( #range(BA, lengthBytes(BA) -Int (log2Int(X +Int 1) /Int 8), log2Int(X +Int 1) /Int 8) ) <=Int Y:Int
     [simplification, concrete(X), preserves-definedness]

    rule X &Int ( Y *Int Z ) => 0
    requires 0 <=Int X andBool 0 <=Int Y andBool 0 <=Int Z
     andBool X +Int 1 ==Int 2 ^Int log2Int(X +Int 1)
     andBool Y ==Int 2 ^Int log2Int(Y)
     andBool log2Int(X +Int 1) <=Int log2Int(Y)
     [simplification, concrete(X, Y), preserves-definedness]

    rule X &Int ( Y *Int Z ) => 0
    requires 0 <=Int X andBool 0 <=Int Y andBool 0 <=Int Z
     andBool X +Int 1 ==Int 2 ^Int log2Int(X +Int 1)
     andBool Z ==Int 2 ^Int log2Int(Z)
     andBool log2Int(X +Int 1) <=Int log2Int(Z)
     [simplification, concrete(X, Z), preserves-definedness]

    rule chop ( X *Int Y ) => X *Int Y
      requires 0 <=Int X andBool X <Int ethUpperBound
       andBool 0 <=Int Y andBool Y <Int 2 ^Int ( 256 -Int ethMaxWidth )
       [simplification]

    rule [mul-overflow-check]:
      X ==Int chop ( X *Int Y ) /Int Y => X *Int Y <Int pow256
      requires #rangeUInt(256, X) andBool 0 <Int Y
      [simplification, comm, preserves-definedness]

    rule [mul-overflow-check-ML]:
      { X #Equals chop ( X *Int Y ) /Int Y } => { true #Equals X *Int Y <Int pow256 }
      requires #rangeUInt(256, X) andBool 0 <Int Y
      [simplification, preserves-definedness]

    rule 0 <=Int keccak(X) => true [simplification, smt-lemma]

    rule X >>Int N => X /Int (2 ^Int N) [simplification, concrete(N)]

    rule #asWord ( BUF1 +Bytes BUF2 ) => #asWord ( BUF2 )
        requires #asWord ( BUF1 ) ==Int 0
        [simplification, concrete(BUF1)]

    //
    //  Master slot-update lemma
    //
    rule ( VALUE:Int *Int SHIFT:Int ) |Int ( MASK_SLOT:Int &Int #asWord ( SLOT:Bytes ) ) =>
         #asWord ( ( #buf ( 32 -Int lengthBytes ( SLOT ), 0 ) +Bytes SLOT ) [ 32 -Int ( log2Int ( ( maxUInt256 xorInt ( ( MASK_SLOT /Int SHIFT ) *Int SHIFT ) ) +Int 1 ) /Int 8 ) :=
                   #buf ( ( log2Int ( ( maxUInt256 xorInt ( ( MASK_SLOT /Int SHIFT ) *Int SHIFT ) ) +Int 1 ) -Int log2Int ( SHIFT ) ) /Int 8, VALUE:Int ) ] )
      requires // Appropriate bounds for SHIFT, MASK_SLOT, and SLOT
               #rangeUInt(256, SHIFT) andBool #rangeUInt(256, MASK_SLOT) andBool lengthBytes(SLOT) <=Int 32
               // Shift is a power of two
       andBool SHIFT ==Int 2 ^Int log2Int(SHIFT)
               // MASK_SLOT preserves all bits below the starting point at log2Int ( SHIFT )
       andBool ( ( SHIFT -Int 1 ) &Int MASK_SLOT ) +Int 1 ==Int SHIFT
               // MASK_SLOT preserves all bits starting from a certain point,
               // which is identified by log2Int ( ( maxUInt256 xorInt ( ( MASK_SLOT /Int SHIFT ) *Int SHIFT ) ) +Int 1 ),
               // and all bits between that point and the starting point are zero
       andBool ( maxUInt256 xorInt ( ( MASK_SLOT /Int SHIFT ) *Int SHIFT ) ) +Int 1 ==Int
               2 ^Int log2Int ( ( maxUInt256 xorInt ( ( MASK_SLOT /Int SHIFT ) *Int SHIFT ) ) +Int 1 )
               // The start and endpoints are multiples of 8
       andBool log2Int ( SHIFT ) modInt 8 ==Int 0
       andBool log2Int ( ( maxUInt256 xorInt ( ( MASK_SLOT /Int SHIFT ) *Int SHIFT ) ) +Int 1 ) modInt 8 ==Int 0
               // VALUE is not wider than the gap
       andBool 0 <=Int VALUE andBool VALUE <Int ( ( maxUInt256 xorInt ( ( MASK_SLOT /Int SHIFT ) *Int SHIFT ) ) +Int 1 ) /Int SHIFT
      [simplification, concrete(SHIFT, MASK_SLOT), preserves-definedness]

    //
    // #lookup
    //
    rule M:Map [ K1 <- _ ] [ K2 <- V2 ] [ K1 <- V3 ] => M:Map [ K2 <- V2 ] [ K1 <- V3 ] [simplification]

    //
    // Rules
    //

    // rule [create-valid-enhanced]:
    //     <k> CREATE VALUE MEMSTART MEMWIDTH
    //     => #accessAccounts #newAddr(ACCT, NONCE)
    //     ~> #checkCreate ACCT VALUE
    //     ~> #create ACCT #newAddr(ACCT, NONCE) VALUE #range(LM, MEMSTART, MEMWIDTH)
    //     ~> #codeDeposit #newAddr(ACCT, NONCE)
    //     ...
    //     </k>
    //     <id> ACCT </id>
    //     <localMem> LM </localMem>
    //     <accounts>
    //       <account>
    //         <acctID> ACCT </acctID>
    //         <nonce> NONCE </nonce>
    //         ...
    //       </account>
    //       ACCOUNTS_REST
    //     </accounts>
    //     <schedule> SCHED </schedule>
    // requires #hasValidInitCode(MEMWIDTH, SCHED)
    //   ensures notBool ( #newAddr(ACCT, NONCE) ==Int ACCT )
    //   andBool notBool ( <acctID> #newAddr(ACCT, NONCE) </acctID> in_keys ( ACCOUNTS_REST:AccountCellMap ) )
    // [priority(30), preserves-definedness]

endmodule

module LIDO-LEMMAS-SPEC
    imports LIDO-LEMMAS

    claim [storage-offset]: <k> runLemma ( ( #lookup ( STORAGE3:Map , 2 ) /Int pow160 ) ) => doneLemma ( #asWord ( #range ( #buf ( 32 , #lookup ( STORAGE3:Map , 2 ) ) , 0 , 12 ) ) ) ... </k>

    claim [chop-simplify]: <k> runLemma (
                                 notBool chop ( WORD7:Int +Int ( WORD12:Int *Int ( ( WORD5:Int -Int WORD6:Int ) /Int WORD11:Int ) ) ) ==Int
                                 chop ( chop ( WORD7:Int +Int ( WORD12:Int *Int ( ( WORD5:Int -Int WORD6:Int ) /Int WORD11:Int ) ) ) *Int 1000000000000000000 ) /Int 1000000000000000000
                               ) => runLemma ( false ) ... </k>
      requires 0 <=Int WORD5:Int
       andBool 0 <=Int WORD6:Int
       andBool 0 <=Int WORD7:Int
       andBool 0 <=Int WORD11:Int
       andBool 0 <=Int WORD12:Int
       andBool WORD11:Int =/=Int 0
       andBool WORD12:Int =/=Int 0
       andBool WORD6:Int <=Int WORD5:Int
       andBool WORD5:Int <Int pow96
       andBool WORD6:Int <Int pow96
       andBool WORD7:Int <Int pow96
       andBool WORD11:Int <Int pow96
       andBool WORD12:Int <Int pow96

    claim [masking-conditions-01]:
      <k> runLemma (
                    #rangeUInt(256, maxUInt40) andBool #rangeUInt(256, 256)
            andBool #rangeUInt(256, 115792089237316195423570985008687907853269984665640564039457583726438152929535)
            andBool lengthBytes(b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , WORD4:Int ) +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes b"\x01") ==Int 32
            andBool maxUInt40 +Int 1 ==Int 2 ^Int log2Int(maxUInt40 +Int 1)
            andBool              256 ==Int 2 ^Int log2Int(256)
            andBool maxUInt40 &Int ( 115792089237316195423570985008687907853269984665640564039457583726438152929535 /Int 256 ) ==Int 0
            andBool log2Int ( ( ( 115792089237316195423570985008687907853269984665640564039457583726438152929535 /Int 256 ) /Int ( maxUInt40 +Int 1 ) ) +Int 1 ) ==Int
                    256 -Int log2Int (256) -Int log2Int (maxUInt40 +Int 1)
            andBool 0 <=Int VALUE andBool VALUE <Int maxUInt40 +Int 1
          ) => doneLemma (
            true
          ) ... </k>
          requires 0 <Int VALUE andBool VALUE <Int pow40

    claim [masking-conditions-02]:
      <k> runLemma (
                    #rangeUInt(256, pow40) andBool #rangeUInt(256, 115792089237316195423570985008687907853269984665640562830531764394383466561535) andBool lengthBytes( #buf ( 1 , WORD7:Int ) +Bytes b"\xa4\xadOh\xd0\xb9\x1c\xfd\x19h|\x88\x1eP\xf3\xa0\x02B\x82\x8c" +Bytes #buf ( 5 , WORD6:Int ) +Bytes #buf ( 5 , WORD5:Int ) ) ==Int X
                    // Shift is a power of two
            andBool pow40 ==Int 2 ^Int log2Int(pow40)
            andBool ( ( pow40 -Int 1 ) &Int 115792089237316195423570985008687907853269984665640562830531764394383466561535 ) +Int 1 ==Int pow40
            andBool ( maxUInt256 xorInt ( ( 115792089237316195423570985008687907853269984665640562830531764394383466561535 /Int pow40 ) *Int pow40 ) ) +Int 1 ==Int
                    2 ^Int log2Int ( ( maxUInt256 xorInt ( ( 115792089237316195423570985008687907853269984665640562830531764394383466561535 /Int pow40 ) *Int pow40 ) ) +Int 1 )
            andBool 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int ( ( maxUInt256 xorInt ( ( 115792089237316195423570985008687907853269984665640562830531764394383466561535 /Int pow40 ) *Int pow40 ) ) +Int 1 ) /Int pow40
          ) => doneLemma (
            true
          ) ... </k>

    claim [master-masking-01]:
      <k> runLemma (
            ( ( maxUInt40 &Int TIMESTAMP_CELL:Int ) *Int 256 ) |Int ( 115792089237316195423570985008687907853269984665640564039457583726438152929535 &Int #asWord ( b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , WORD4:Int ) +Bytes #buf ( 5 , _WORD3:Int ) +Bytes b"\x01" ) )
          ) => doneLemma (
            #asWord ( b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , WORD4:Int ) +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes b"\x01" )
          ) ... </k>
          requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int pow40

    claim [storage-simplification]:
      <k> runLemma (
            STORAGE0:Map
            [ 5 <- #asWord ( b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , WORD4:Int ) +Bytes #buf ( 5 , WORD3:Int ) +Bytes b"\x00" ) ]
            [ 6 <- #asWord ( #buf ( 1 , WORD7:Int ) +Bytes b"\xa4\xadOh\xd0\xb9\x1c\xfd\x19h|\x88\x1eP\xf3\xa0\x02B\x82\x8c" +Bytes #buf ( 5 , WORD6:Int ) +Bytes #buf ( 5 , WORD5:Int ) ) ]
            [ 5 <- #asWord ( b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , WORD4:Int ) +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes b"\x01" ) ]
            [ 6 <- ( ( TIMESTAMP_CELL:Int *Int pow40 ) |Int ( 115792089237316195423570985008687907853269984665640562830531764394383466561535 &Int #asWord ( #buf ( 1 , WORD7:Int ) +Bytes b"\xa4\xadOh\xd0\xb9\x1c\xfd\x19h|\x88\x1eP\xf3\xa0\x02B\x82\x8c" +Bytes #buf ( 5 , WORD6:Int ) +Bytes #buf ( 5 , WORD5:Int ) ) ) ) ]
            [ 5 <- #asWord ( b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes b"\x01" ) ]
          ) => doneLemma (
            STORAGE0:Map
            [ 6 <- #asWord ( #buf ( 1 , WORD7:Int ) +Bytes b"\xa4\xadOh\xd0\xb9\x1c\xfd\x19h|\x88\x1eP\xf3\xa0\x02B\x82\x8c" +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes #buf ( 5 , WORD5:Int ) ) ]
            [ 5 <- #asWord ( b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes b"\x01" ) ]
          ) ... </k>
          requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int pow40
endmodule