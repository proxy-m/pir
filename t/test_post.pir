# There is no way to .loadlib io_ops from nqp...
.loadlib 'io_ops'

.sub "test_post"
    .param string test_name
    .param string code
    .param string expected
    .param pmc    adverbs
    .local string stages, target

    $I0 = exists adverbs['stages']
    unless $I0 goto default_stages
    stages = adverbs['stages']
    goto stages_done
default_stages:
    stages = 'parse post pbc'
stages_done:
    $I0 = exists adverbs['target']
    unless $I0 goto default_target
    target = adverbs['target']
    goto target_done
default_target:
    target = 'post'
target_done:

    .include "test_more.pir"
    load_bytecode "pir.pbc"
    load_bytecode "dumper.pbc"
    load_bytecode "PGE/Dumper.pbc"

    #pir::trace(4);
    .local pmc c
    c = compreg 'PIRATE'
    $P0 = split ' ', stages
    c.'stages'($P0)

    .local pmc post
    push_eh fail
    post = c.'compile'(code, "target" => target)

    # XXX dumper always dump to stdout...
    .local pmc o, n
    o = getstdout
    n = new ['StringHandle']
    n.'open'('foo', "w")
    setstdout n
    c.'dumper'(post, target)
    setstdout o

    $S0 = n.'readall'()

    is($S0, expected, test_name)
    .return()

  fail:
    pop_eh
    .local pmc exception
    .get_results (exception)

    $S0 = adverbs['fail_like']
    if null $S0 goto check_todo
    $S1 = exception
    $I0 = index $S1, $S0
    $I1 = $I0 != -1
    ok($I1, test_name)
    diag(exception)
    diag($S0)
    .return()

  check_todo:
    $S0 = adverbs['todo']
    if null $S0 goto check_fail
    todo($S0)

  check_fail:
    $I0 = adverbs['fail']
    ok($I0, test_name)
    .return()

#    CATCH {
#        ok(%adverbs<fail>, $test_name);
#        diag("POST failed $!");
#    };
.end


# vim: ft=pir
