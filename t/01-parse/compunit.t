#!parrot

.include 't/common.pir'
.sub "main" :main
    .local pmc tests

    load_bytecode 'pir.pbc'
    .include 'test_more.pir'

    tests = 'get_tests'()
    'test_parse'(tests)
.end

.sub "get_tests"
    .local pmc tests
    tests = new ['ResizablePMCArray']

    $P0 = 'make_test'( <<'CODE', 'const defs' )

.const int iConst = 42

.const num nConst = 3.14

.const string sConst = "Hello World"

.const pmc pConst = "is a PMC const a string?"

CODE
    push tests, $P0




    $P0 = 'make_test'( <<'CODE', 'loadlib directive' )

.loadlib "Hitchhikers"

CODE
    push tests, $P0

    $P0 = 'make_test'( <<'CODE', 'n_operators directive' )

.pragma n_operators 1

CODE
    push tests, $P0


    $P0 = 'make_test'( <<'CODE', 'namespaces 1' )

.namespace ['']
.namespace [""]

CODE
    push tests, $P0


    $P0 = 'make_test'( <<'CODE', 'namespaces 2' )

.namespace ['PIR']
.namespace ["PIR"]

CODE
    push tests, $P0


    $P0 = 'make_test'( <<'CODE', 'namespaces 3' )

.namespace ['PIR';'Grammar']
.namespace ["PIR";"Grammar"]

CODE
    push tests, $P0

    $P0 = 'make_test'( <<'CODE', 'Root namespace', 'todo' => 'Failing' )

.namespace []

CODE
    push tests, $P0

    $P0 = 'make_test'( <<'CODE', 'HLL', 'todo' => 'Failing' )

.HLL 'PIR', 'PIRlib'
.HLL "PIR", "PIRlib"

CODE
    push tests, $P0

    $P0 = 'make_test'( <<'CODE', 'HLL map', 'todo' => 'Failing' )

.HLL_map "Integer", "FooNumber"

CODE
    push tests, $P0

    $P0 = 'make_test'( <<'CODE', 'source line info' )

.line 42

.line 42, "Hitchhikers.pir"

CODE
    push tests, $P0


    $P0 = 'make_test'( <<'CODE', 'emit', 'todo' => 'Failing' )

.emit
	set P0, 1
.eom

CODE
    push tests, $P0
    
    .return (tests)
.end

