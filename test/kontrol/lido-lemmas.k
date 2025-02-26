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

    rule C <=Int A *Int B => C /Int A <=Int B
      requires 0 <=Int C andBool 0 <Int A
       andBool C modInt A ==Int 0
       [simplification(40), concrete(C, A), preserves-definedness]

    rule A ==Int B => false
      requires 0 <=Int A andBool B <Int 0
      [simplification, concrete(B)]

    rule 0 <=Int A -Int B => B <=Int A
      [simplification, symbolic(A, B)]

    rule ( ( A *Int B ) +Int C ) /Int D => ( ( ( A /Int 10 ) *Int B ) +Int ( ( D /Int 10 ) -Int 1 ) ) /Int ( D /Int 10 )
      requires 0 <=Int A andBool 0 <Int D
       andBool A modInt 10 ==Int 0 andBool D modInt 10 ==Int 0 andBool C ==Int D -Int 1
       [simplification, concrete(A, C, D), preserves-definedness]

    rule [asWord-lt-concat-left]:
      #asWord ( BA1 +Bytes BA2 ) <Int X => #asWord ( BA1 ) <Int X /Int ( 2 ^Int ( 8 *Int lengthBytes ( BA2 ) ) )
      requires X modInt ( 2 ^Int ( 8 *Int lengthBytes ( BA2 ) ) ) ==Int 0
      [simplification, preserves-definedness]

    rule [notBool-or]:  notBool ( A  orBool B ) => ( notBool A ) andBool ( notBool B ) [simplification]
    rule [notBool-and]: notBool ( A andBool B ) => ( notBool A )  orBool ( notBool B ) [simplification]

    rule 0 <Int X => true requires 0 <=Int X andBool notBool (X ==Int 0) [simplification(60)]

    rule X *Int Y <Int Z => Y <Int Z /Int X
      requires 0 <Int X andBool 0 <=Int Z andBool Z modInt X ==Int 0
      [simplification, concrete(X, Z), preserves-definedness]

    rule X <=Int maxUInt256 => X <Int pow256 [simplification]

    // Simplifications for the OpenZeppelin ternary operator function

    rule [xorInt-ge-zero]:
      0 <=Int X xorInt Y => true
      requires 0 <=Int X andBool 0 <=Int Y
      [simplification]

    rule [xorInt-lt]:
      X xorInt Y <Int Z => true
      requires X <Int ( 2 ^Int log2Int ( Z ) ) andBool Y <Int ( 2 ^Int log2Int ( Z ) )
      [simplification, concrete(Z)]

    rule [b2w-lt]:
      bool2Word ( B:Bool ) *Int X <Int Y =>
        ( ( notBool B ) andBool 0 <=Int Y ) orBool ( B andBool X <Int Y )
      [simplification, concrete(Y)]

    rule [xorInt-to-if]:
      X xorInt ( bool2Word ( B ) *Int ( X xorInt Y ) ) => #if B #then Y #else X #fi
      [simplification]

    //
    //  Different approach to #lookup
    //

    // Symbolic lookup of map update
    rule ( _:Map [ K1 <- V ] ):Map [ K2 ] => V            requires         K1 ==K K2 [simplification(45), preserves-definedness]
    rule ( M:Map [ K1 <- _ ] ):Map [ K2 ] => M:Map [ K2 ] requires notBool K1 ==K K2 [simplification(45), preserves-definedness]

    // Symbolic membership of map update
    rule K1 in_keys( _:Map [ K2 <- _ ] ) => true          requires         K1 ==K K2 [simplification(45), preserves-definedness]
    rule K1 in_keys( M:Map [ K2 <- _ ] ) => K1 in_keys(M) requires notBool K1 ==K K2 [simplification(45), preserves-definedness]

    // #lookup when key is present in map
    rule #lookup( M:Map, K:Int ) => #if isInt( M:Map [ K ] ) #then { M:Map [ K ] }:>Int modInt pow256 #else 0 #fi
      requires K in_keys( M:Map )
      [priority(20), preserves-definedness]

    // #lookup when key is absent in map
    rule #lookup( M:Map, K:Int ) => 0
      requires notBool K in_keys( M:Map )
      [priority(25), preserves-definedness]

    //
    //  KEVM Improvements
    //

    // Direct buffer resolution for auxiliary functions
    rule #addrBytes(ACCT) => #buf(20, ACCT) requires #rangeAddress(ACCT)   [priority(40), preserves-definedness]
    rule #wordBytes(WORD) => #buf(32, WORD) requires #rangeUInt(256, WORD) [priority(40), preserves-definedness]

    // Direct buffer resolution for MSTORE
    rule <k> MSTORE INDEX VALUE => .K ... </k>
         <localMem> LM => LM [ INDEX := #buf(32, VALUE) ] </localMem>
         requires #rangeUInt(256, VALUE)
         [priority(40), preserves-definedness]

    //
    // keccak
    //
    rule [keccak-slots-disjoint]: keccak ( A ) ==Int keccak ( B ) +Int C => false requires notBool C ==Int 0 [simplification, concrete(C), comm]

    rule [keccak-slots-disjoint-ml-l]: { keccak ( A ) #Equals keccak ( B ) +Int C } => #Bottom requires notBool C ==Int 0 [simplification, concrete(C)]
    rule [keccak-slots-disjoint-ml-r]: { keccak ( B ) +Int C #Equals keccak ( A ) } => #Bottom requires notBool C ==Int 0 [simplification, concrete(C)]

    //
    // Argument encoding for booster
    //
    rule #encodeArgs(ARGS) => #encodeArgsAux(ARGS, #lenOfHeads(ARGS), .Bytes, .Bytes) [priority(45), preserves-definedness]

    rule #encodeArgsAux( .TypedArgs,  _:Int, HEADS, TAILS) => HEADS +Bytes TAILS [priority(45), preserves-definedness]
    rule #encodeArgsAux((ARG, ARGS), OFFSET, HEADS, TAILS) => #encodeArgsAux(ARGS, OFFSET, HEADS +Bytes #enc(ARG), TAILS) requires #isStaticType(ARG) [priority(45), preserves-definedness]
    rule #encodeArgsAux((ARG, ARGS), OFFSET, HEADS, TAILS) => #encodeArgsAux(ARGS, OFFSET +Int #sizeOfDynamicType(ARG), HEADS +Bytes #enc(#uint256(OFFSET)), TAILS +Bytes #enc(ARG)) requires notBool(#isStaticType(ARG)) [priority(45), preserves-definedness]

    rule #enc(#bytes(BS)) => #encBytes(lengthBytes(BS), BS) ensures lengthBytes(BS) <=Int 1073741824 [priority(45), preserves-definedness]
    rule #encBytes(N, BS) => #enc(#uint256(N)) +Bytes BS +Bytes #bufStrict(#ceil32(N) -Int N, 0) [priority(45), preserves-definedness]
    rule #enc(#uint256(DATA)) => #bufStrict(32, #getValue(#uint256(DATA))) [priority(45), preserves-definedness]
    rule #getValue(#uint256(X)) => X requires #rangeUInt(256, X) [priority(45), preserves-definedness]

    rule #encodeOutput(BA) => #abiCallData("expectRevert", #bytes(BA)) requires notBool #range(BA, 0, 4) ==K Int2Bytes(4, selector("Error(string)"), BE) [preserves-definedness]
    rule #encodeOutput(BA) => BA                                       requires         #range(BA, 0, 4) ==K Int2Bytes(4, selector("Error(string)"), BE) [preserves-definedness]

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

    // Removing function selector from #abiCallData
    rule #range ( #abiCallData ( FNAME , ARGS ) , 4 , LENGTH ) => #encodeArgs ( ARGS )
        requires LENGTH ==Int lengthBytes ( #abiCallData ( FNAME , ARGS ) ) -Int 4
        [simplification, preserves-definedness]

    rule ( A /Int B ) /Int C => 0
        requires 0 <=Int A
         andBool 0 <Int B
         andBool 0 <Int C
         andBool A <Int ( C *Int B )
        [simplification, symbolic(A, B), concrete(C), preserves-definedness]

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

    claim [slot-update-01]:
      <k> runLemma(
        ( maxUInt8 &Int ( ( TIMESTAMP_CELL:Int *Int pow48 ) |Int ( 115792089237316195423570985008687907853269984665640254554447762944319381569535 &Int ( ( TIMESTAMP_CELL:Int *Int 256 ) |Int ( 115792089237316195423570985008687907853269984665640564039457583726438152929535 &Int ( 1 |Int #asWord ( b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , _WORD4:Int ) +Bytes #buf ( 5 , _WORD3:Int ) +Bytes b"\x00" ) ) ) ) ) ) )
      ) => doneLemma(
        1
      ) ... </k>
      requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int 2 ^Int 40

    claim [slot-update-02]:
      <k> runLemma (
            ( ( maxUInt40 &Int ( ( 115341543235797707419527244145998463631733976271937281205136574426583511597055 &Int #asWord ( #buf ( 2 , WORD7:Int ) +Bytes b"\xa4\xadOh\xd0\xb9\x1c\xfd\x19h|\x88\x1eP\xf3\xa0\x02B\x82\x8c" +Bytes #buf ( 5 , TIMESTAMP_CELL:Int ) +Bytes #buf ( 5 , WORD5:Int ) ) ) /Int pow40 ) ) )
          ) => doneLemma (
            TIMESTAMP_CELL
          ) ... </k>
          requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int 2 ^Int 35

    claim [slot-update-03]:
      <k> runLemma (
            ( maxUInt40 &Int ( ( TIMESTAMP_CELL:Int |Int ( 115792089237316195423570985008687907853269984665640564039457584006813618012160 &Int #asWord ( #buf ( 1 , WORD7:Int ) +Bytes b"\xa4\xadOh\xd0\xb9\x1c\xfd\x19h|\x88\x1eP\xf3\xa0\x02B\x82\x8c" +Bytes #buf ( 5 , WORD6:Int ) +Bytes #buf ( 5 , WORD5:Int ) ) ) ) /Int pow40 ) ) <=Int TIMESTAMP_CELL:Int
          ) => doneLemma (
            true
          ) ... </k>
          requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int 2 ^Int 35

    claim [slot-update-04]:
      <k> runLemma (
            #asWord ( #range ( #buf ( 10 , ( ( ( TIMESTAMP_CELL:Int *Int pow48 ) /Int 256 ) |Int TIMESTAMP_CELL:Int ) ) , 5 , 5 ) ) <=Int TIMESTAMP_CELL:Int
          ) => doneLemma (
            true
          ) ... </k>
          requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int 2 ^Int 35

    claim [slot-update-05]:
      <k> runLemma (
            #asWord ( #range ( #buf ( 6 , TIMESTAMP_CELL:Int *Int 256 ) , 5 , 1 ) )
          ) => doneLemma (
            false
          ) ... </k>
          requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int 2 ^Int 35

    claim [slot-update-06]:
      <k> runLemma (
            #asWord ( #range ( #buf ( 26 , 960911443338137442927181681227604902095826437272264907948032 |Int WORD4:Int ) , 21 , 5 ) ) <=Int TIMESTAMP_CELL:Int
          ) => doneLemma (
            WORD4 <=Int TIMESTAMP_CELL
          ) ... </k>
          requires 0 <=Int WORD4 andBool WORD4 <Int 2 ^Int 40

    claim [slot-update-07]:
      <k> runLemma (
            #asWord ( #range ( #buf ( 25 , ( ( ( WORD7:Int +Int 1 ) *Int pow200 ) |Int #asWord ( #buf ( 25 , ( 438052756531465687819472504520361015472122898704787692322816 |Int WORD6:Int ) ) ) ) ) , 20 , 5 ) ) <=Int TIMESTAMP_CELL:Int
          ) => doneLemma (
            WORD6 <=Int TIMESTAMP_CELL
          ) ... </k>
          requires 0 <=Int WORD6 andBool WORD6 <Int 2 ^Int 40
           andBool 0 <=Int WORD7 andBool WORD7 <Int 256

    claim [slot-update-08]:
      <k> runLemma (
            #asWord ( #buf ( 20 , 770621190285571058874329108704665103402425909248 |Int ( ( WORD7:Int +Int 1 ) *Int pow160 ) ) )
          ) => doneLemma (
            770621190285571058874329108704665103402425909248
          ) ... </k>
          requires 0 <=Int WORD7 andBool WORD7 <Int 256

    claim [slot-update-09]:
      <k> runLemma (
            ( 481644099385675654177479669474857658256926169505224677670350078624137216 |Int ( 115790322390251417039241401711187164934754157181743689629425282016341011726335 &Int #asWord ( #buf ( 2 , WORD7:Int ) +Bytes b"\xa4\xadOh\xd0\xb9\x1c\xfd\x19h|\x88\x1eP\xf3\xa0\x02B\x82\x8c" +Bytes #buf ( 5 , WORD6:Int ) +Bytes #buf ( 5 , WORD5:Int ) ) ) )
          ) => doneLemma (
            #asWord ( #buf ( 2 , WORD7:Int ) +Bytes b"E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , WORD6:Int ) +Bytes #buf ( 5 , WORD5:Int ) )
          ) ... </k>
          requires 0 <=Int WORD5 andBool WORD5 <Int 2 ^Int 35
           andBool 0 <=Int WORD6 andBool WORD6 <Int 2 ^Int 35
           andBool 0 <=Int WORD7 andBool WORD7 <Int 256

endmodule