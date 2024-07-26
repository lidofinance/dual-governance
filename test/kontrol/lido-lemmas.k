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

    // chop and +Int
    rule [chop-plus]: chop (A +Int B) ==Int 0 => A ==Int (-1) *Int B
      requires #rangeUInt(256, A) andBool #rangeUInt(256, (-1) *Int B)
      [concrete(B), simplification, comm]

    // chop and -Int
    rule [chop-zero-minus]: chop (0 -Int A) ==Int B => A ==Int (pow256 -Int B) modInt pow256
      requires #rangeUInt(256, A) andBool #rangeUInt(256, B)
      [concrete(B), simplification, comm, preserves-definedness]

    // ==Int
    rule [int-eq-refl]: X ==Int X => true [simplification]

    // *Int
    rule A *Int B ==Int 0 => A ==Int 0 orBool B ==Int 0 [simplification]

    // /Int
    rule 0 /Int B         => 0         requires B =/=Int 0 [simplification, preserves-definedness]
    rule A /Int B ==Int 0 => A ==Int 0 requires B =/=Int 0 [simplification, preserves-definedness]

    // /Word
    rule  _ /Word W1 => 0          requires W1  ==Int 0 [simplification]
    rule W0 /Word W1 => W0 /Int W1 requires W1 =/=Int 0 [simplification, preserves-definedness]

    // Further /Int and /Word arithmetic
    rule ( X *Int Y ) /Int Y => X requires Y =/=Int 0              [simplification, preserves-definedness]
    rule ( X *Int Y ) /Int X => Y requires X =/=Int 0              [simplification, preserves-definedness]
    rule ( X ==Int ( X *Int Y ) /Word Y ) orBool Y ==Int 0 => true [simplification, preserves-definedness]
    rule ( X ==Int ( Y *Int X ) /Word Y ) orBool Y ==Int 0 => true [simplification, preserves-definedness]
    rule ( 0 ==Int          0   /Word Y ) orBool Y ==Int 0 => true [simplification, preserves-definedness]

    rule A <=Int B /Int C =>         A  *Int C <=Int B requires 0 <Int C [simplification, preserves-definedness]
    rule A  <Int B /Int C => (A +Int 1) *Int C <=Int B requires 0 <Int C [simplification, preserves-definedness]
    rule A  >Int B /Int C =>         A  *Int C  >Int B requires 0 <Int C [simplification, preserves-definedness]
    rule A >=Int B /Int C => (A +Int 1) *Int C  >Int B requires 0 <Int C [simplification, preserves-definedness]

    rule B /Int C >=Int A =>         A  *Int C <=Int B requires 0 <Int C [simplification, preserves-definedness]
    rule B /Int C  >Int A => (A +Int 1) *Int C <=Int B requires 0 <Int C [simplification, preserves-definedness]
    rule B /Int C  <Int A =>         A  *Int C  >Int B requires 0 <Int C [simplification, preserves-definedness]
    rule B /Int C <=Int A => (A +Int 1) *Int C  >Int B requires 0 <Int C [simplification, preserves-definedness]

    // More specialised /Int and /Word arithmetic
    rule ( X ==Int ( X *Int ( Y +Int C ) ) /Word ( Y +Int C ) ) orBool Y ==Int D => true
      requires C +Int D ==Int 0 [simplification, preserves-definedness]


    // Further generalization of: maxUIntXXX &Int #asWord ( BA )
    rule X &Int #asWord ( BA ) => #asWord ( #range(BA, lengthBytes(BA) -Int (log2Int(X +Int 1) /Int 8), log2Int(X +Int 1) /Int 8) )
    requires #rangeUInt(256, X)
     andBool X +Int 1 ==Int 2 ^Int log2Int(X +Int 1)
     andBool log2Int (X +Int 1) modInt 8 ==Int 0
     andBool (log2Int (X +Int 1)) /Int 8 <=Int lengthBytes(BA) andBool lengthBytes(BA) <=Int 32
     [simplification, concrete(X), preserves-definedness]

    // #asWord
    rule #asWord ( B1 +Bytes B2 ) => #asWord ( B2 )
        requires #asWord ( B1 ) ==Int 0
        [simplification, concrete(B1)]

    rule #asWord( BA ) >>Int N => #asWord( #range ( BA, 0, lengthBytes( BA ) -Int ( N /Int 8 ) ) )
    requires 0 <=Int N andBool N modInt 8 ==Int 0
    [simplification, concrete(N), preserves-definedness]

    // >>Int
    rule [shift-to-div]: X >>Int N => X /Int (2 ^Int N) [simplification(60), concrete(N)]

    // Boolean equality
    rule B ==K false => notBool B [simplification(30), comm]
    rule B ==K true  =>         B [simplification(30), comm]

    // bool2Word
    rule bool2Word(X)  ==Int 0 => notBool X [simplification(30), comm]
    rule bool2Word(X) =/=Int 0 => X         [simplification(30), comm]
    rule bool2Word(X)  ==Int 1 => X         [simplification(30), comm]
    rule bool2Word(X) =/=Int 1 => notBool X [simplification(30), comm]

    rule [bool2Word-lt-true]:  bool2Word(_:Bool) <Int X:Int => true      requires 1 <Int X [simplification(30), concrete(X)]
    rule [bool2Word-lt-one]:   bool2Word(B:Bool) <Int 1     => notBool B                   [simplification(30)]
    rule [bool2Word-gt-zero]:  0 <Int bool2Word(B:Bool)     => B                           [simplification(30)]
    rule [bool2Word-gt-false]: X:Int <Int bool2Word(_:Bool) => false     requires 1 <Int X [simplification(30), concrete(X)]

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

    //
    //  Overflows and ranges
    //
    rule X <=Int A +Int B => true requires X <=Int 0 andBool 0 <=Int A andBool 0 <=Int B [concrete(X), simplification, preserves-definedness]
    rule X <=Int A *Int B => true requires X <=Int 0 andBool 0 <=Int A andBool 0 <=Int B [concrete(X), simplification, preserves-definedness]
    rule X <=Int A /Int B => true requires X <=Int 0 andBool 0 <=Int A andBool 0  <Int B [concrete(X), simplification, preserves-definedness]

    rule X <Int A +Int B => true requires X <=Int 0 andBool 0  <Int A andBool 0 <=Int B [concrete(X), simplification]
    rule X <Int A +Int B => true requires X <=Int 0 andBool 0 <=Int A andBool 0  <Int B [concrete(X), simplification]
    rule X <Int A *Int B => true requires X <=Int 0 andBool 0  <Int A andBool 0  <Int B [concrete(X), simplification]
    rule X <Int A /Int B => true requires X <=Int 0 andBool 0  <Int A andBool 0  <Int B [concrete(X), simplification, preserves-definedness]

    rule [chop-no-overflow-add-l]: X:Int <=Int chop ( X +Int Y:Int ) => X +Int Y <Int pow256 requires #rangeUInt(256, X) andBool #rangeUInt(256, Y)             [simplification]
    rule [chop-no-overflow-add-r]: X:Int <=Int chop ( Y +Int X:Int ) => X +Int Y <Int pow256 requires #rangeUInt(256, X) andBool #rangeUInt(256, Y)             [simplification]
    rule [chop-no-overflow-mul-l]: X:Int <=Int chop ( X *Int Y:Int ) => X *Int Y <Int pow256 requires #rangeUInt(256, X) andBool #rangeUInt(256, Y)             [simplification]
    rule [chop-no-overflow-mul-r]: X:Int <=Int chop ( Y *Int X:Int ) => X *Int Y <Int pow256 requires #rangeUInt(256, X) andBool #rangeUInt(256, Y)             [simplification]
    rule [chop-no-overflow-div]:   X:Int <=Int chop ( X /Int Y:Int ) => X /Int Y <Int pow256 requires #rangeUInt(256, X) andBool 0 <Int Y andBool Y <Int pow256 [simplification]

    //
    //  Master slot-update lemma
    //

    // Auxiliaries

    syntax Int ::=  #getFirstOneBit(Int) [function, total]
    syntax Int ::= #getFirstZeroBit(Int) [function, total]

    rule #getFirstOneBit(X:Int) => log2Int ( X &Int ( ( maxUInt256 xorInt X ) +Int 1 ) ) requires         #rangeUInt(256, X) [concrete(X), simplification]
    rule #getFirstOneBit(X:Int) => -1                                                    requires notBool #rangeUInt(256, X) [concrete(X), simplification]

    rule #getFirstZeroBit(X:Int) => #getFirstOneBit ( maxUInt256 xorInt X ) requires         #rangeUInt(256, X) [concrete(X), simplification]
    rule #getFirstZeroBit(X:Int) => -1                                      requires notBool #rangeUInt(256, X) [concrete(X), simplification]

    syntax Int ::= #getMaskShiftBits(Int)  [function, total]
    syntax Int ::= #getMaskShiftBytes(Int) [function, total]

    rule #getMaskShiftBits(X:Int)  => #getFirstZeroBit(X) [concrete(X), simplification]

    rule #getMaskShiftBytes(X:Int) => #getFirstZeroBit(X) /Int 8 requires           #getMaskShiftBits(X) modInt 8 ==Int 0   [concrete(X), simplification, preserves-definedness]
    rule #getMaskShiftBytes(X:Int) => -1                         requires notBool ( #getMaskShiftBits(X) modInt 8 ==Int 0 ) [concrete(X), simplification, preserves-definedness]

    syntax Int ::= #getMaskWidthBits(Int)  [function, total]
    syntax Int ::= #getMaskWidthBytes(Int) [function, total]

    rule #getMaskWidthBits(X:Int) => #getFirstOneBit(X >>Int #getMaskShiftBits(X:Int)) requires         #rangeUInt(256, X) [concrete(X), simplification]
    rule #getMaskWidthBits(X:Int) => -1                                                requires notBool #rangeUInt(256, X) [concrete(X), simplification]

    rule #getMaskWidthBytes(X:Int) => #getMaskWidthBits(X) /Int 8 requires           #getMaskWidthBits(X) modInt 8 ==Int 0   [concrete(X), simplification, preserves-definedness]
    rule #getMaskWidthBytes(X:Int) => -1                          requires notBool ( #getMaskWidthBits(X) modInt 8 ==Int 0 ) [concrete(X), simplification, preserves-definedness]

    syntax Bool ::= #isMask(Int) [function, total]

    rule #isMask(X:Int) => maxUInt256 ==Int X |Int ( 2 ^Int ( #getMaskShiftBits(X) +Int #getMaskWidthBits(X) ) -Int 1 )
      requires 0 <=Int #getMaskShiftBytes(X) andBool 0 <=Int #getMaskWidthBytes(X)
      [concrete(X), simplification, preserves-definedness]

    rule #isMask(X:Int) => false
      requires notBool ( 0 <=Int #getMaskShiftBytes(X) andBool 0 <=Int #getMaskWidthBytes(X) )
      [concrete(X), simplification, preserves-definedness]

    // Actual masking lemmas

    // |Int and +Bytes, into right
    rule A |Int #asWord ( B1 +Bytes B2 ) =>
      #asWord ( B1 +Bytes #buf ( lengthBytes(B2), A |Int #asWord ( B2 ) ) )
      requires 0 <=Int A andBool A <Int 2 ^Int (8 *Int lengthBytes(B2))
      [simplification(60)]

    // Update: value symbolic, slot symbolic
    rule ( VALUE:Int *Int SHIFT:Int ) |Int ( MASK:Int &Int #asWord ( SLOT:Bytes ) ) =>
        #asWord ( ( #buf ( 32 -Int lengthBytes ( SLOT ), 0 ) +Bytes SLOT )
                  [ 32 -Int ( #getMaskShiftBytes(MASK) +Int #getMaskWidthBytes(MASK) ) :=
                    #buf ( #getMaskWidthBytes(MASK), VALUE:Int ) ] )
      requires #rangeUInt(256, SHIFT) andBool #rangeUInt(256, MASK) andBool lengthBytes(SLOT) <=Int 32
       andBool #isMask(MASK)
       andBool SHIFT ==Int 2 ^Int log2Int(SHIFT)
       andBool #getMaskShiftBits(MASK) ==Int log2Int(SHIFT)
       andBool 0 <=Int VALUE andBool VALUE <Int 2 ^Int #getMaskWidthBits(MASK)
       [simplification, concrete(SHIFT, MASK), preserves-definedness]

    // Update: value concrete, slot symbolic
    rule VALUE |Int ( MASK:Int &Int #asWord ( SLOT:Bytes ) ) =>
        #asWord ( ( #buf ( 32 -Int lengthBytes ( SLOT ), 0 ) +Bytes SLOT )
                  [ 32 -Int ( #getMaskShiftBytes(MASK) +Int #getMaskWidthBytes(MASK) ) :=
                    #buf ( #getMaskWidthBytes(MASK), VALUE >>Int #getMaskShiftBits(MASK) ) ] )
      requires #rangeUInt(256, MASK) andBool lengthBytes(SLOT) <=Int 32
       andBool #isMask(MASK)
       andBool 0 <=Int ( VALUE >>Int #getMaskShiftBits(MASK) )
       andBool ( VALUE >>Int #getMaskShiftBits(MASK) ) <Int 2 ^Int #getMaskWidthBits(MASK)
       [simplification, concrete(VALUE, MASK), preserves-definedness]

    //
    // #lookup
    //
    rule M:Map [ K1 <- _ ] [ K1 <- V2 ]                                                                               => M:Map [ K1 <- V2 ] [simplification]
    rule M:Map [ K1 <- _ ] [ K2 <- V2 ] [ K1 <- V3 ]                                                                  => M:Map [ K2 <- V2 ] [ K1 <- V3 ] [simplification]
    rule M:Map [ K1 <- _ ] [ K2 <- V2 ] [ K3 <- V3 ] [ K1 <- V4 ]                                                     => M:Map [ K2 <- V2 ] [ K3 <- V3 ] [ K1 <- V4 ] [simplification]
    rule M:Map [ K1 <- _ ] [ K2 <- V2 ] [ K3 <- V3 ] [ K4 <- V4 ] [ K1 <- V5 ]                                        => M:Map [ K2 <- V2 ] [ K3 <- V3 ] [ K4 <- V4 ] [ K1 <- V5 ] [simplification]
    rule M:Map [ K1 <- _ ] [ K2 <- V2 ] [ K3 <- V3 ] [ K4 <- V4 ] [ K5 <- V5 ] [ K1 <- V6 ]                           => M:Map [ K2 <- V2 ] [ K3 <- V3 ] [ K4 <- V4 ] [ K5 <- V5 ] [ K1 <- V6 ] [simplification]
    rule M:Map [ K1 <- _ ] [ K2 <- V2 ] [ K3 <- V3 ] [ K4 <- V4 ] [ K5 <- V5 ] [ K6 <- V6 ] [ K1 <- V7 ]              => M:Map [ K2 <- V2 ] [ K3 <- V3 ] [ K4 <- V4 ] [ K5 <- V5 ] [ K6 <- V6 ] [ K1 <- V7 ] [simplification]
    rule M:Map [ K1 <- _ ] [ K2 <- V2 ] [ K3 <- V3 ] [ K4 <- V4 ] [ K5 <- V5 ] [ K6 <- V6 ] [ K7 <- V7 ] [ K1 <- V8 ] => M:Map [ K2 <- V2 ] [ K3 <- V3 ] [ K4 <- V4 ] [ K5 <- V5 ] [ K6 <- V6 ] [ K7 <- V7 ] [ K1 <- V8 ] [simplification]

    //
    // keccak assumptions: these assumptions are not sound in principle, but are
    // required for verification - they should ideally be collected at the end of execution
    //

    rule 0 <=Int keccak( _ )             => true [simplification, smt-lemma]
    rule         keccak( _ ) <Int pow256 => true [simplification, smt-lemma]

    // keccak does not equal a concrete value
    rule [keccak-eq-conc-false]: keccak(_A)  ==Int _B => false [symbolic(_A), concrete(_B), simplification(30), comm]
    rule [keccak-neq-conc-true]: keccak(_A) =/=Int _B => true  [symbolic(_A), concrete(_B), simplification(30), comm]
    rule [keccak-eq-conc-false-ml-lr]: { keccak(A) #Equals B } => { true #Equals keccak(A) ==Int B } [symbolic(A), concrete(B), simplification]
    rule [keccak-eq-conc-false-ml-rl]: { B #Equals keccak(A) } => { true #Equals keccak(A) ==Int B } [symbolic(A), concrete(B), simplification]

    // keccak is injective
    rule [keccak-inj]: keccak(A) ==Int keccak(B) => A ==K B [simplification]
    rule [keccak-inj-ml]: { keccak(A) #Equals keccak(B) } => { true #Equals A ==K B } [simplification]

    // chop of negative keccak
    rule chop (0 -Int keccak(BA)) => pow256 -Int keccak(BA)
       [simplification]

    // keccak cannot equal a number outside of its range
    rule { X #Equals keccak (_) } => #Bottom
      requires X <Int 0 orBool X >=Int pow256
      [concrete(X), simplification]


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

    claim [masking-01]:
      <k> runLemma(
        ( maxUInt8 &Int ( ( TIMESTAMP_CELL:Int *Int pow48 ) |Int ( 115792089237316195423570985008687907853269984665640254554447762944319381569535 &Int ( ( TIMESTAMP_CELL:Int *Int 256 ) |Int ( 115792089237316195423570985008687907853269984665640564039457583726438152929535 &Int ( 1 |Int #asWord ( b"\x00E\xc9,,\xd0\xdf{-p^\xf1,\xffw\xcb\x0b\xc5W\xed\"" +Bytes #buf ( 5 , _WORD4:Int ) +Bytes #buf ( 5 , _WORD3:Int ) +Bytes b"\x00" ) ) ) ) ) ) )
      ) => doneLemma(
        1
      ) ... </k>
      requires 0 <=Int TIMESTAMP_CELL andBool TIMESTAMP_CELL <Int 2 ^Int 40

endmodule