#!parrot

.sub "main"
    .local pmc tests

    tests = 'get_tests'()
    'test_past'(tests)
.end

.include 't/common.pir'
.include 't/data/sym.pir'

