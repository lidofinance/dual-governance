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

    claim [length-bytestack]: <k> runLemma ( lengthBytes ( #padToWidth ( 32 , #asByteStack ( ( ( ( ( ( ?WORD0:Int *Int VV0_amount_114b9705:Int ) /Int ?WORD:Int ) +Int ?WORD8:Int ) |Int #asWord ( #buf ( 16 , ?WORD9:Int ) +Bytes b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ) ) /Int pow128 ) ) ) ) ) => doneLemma ( 32 ) ... </k>

endmodule