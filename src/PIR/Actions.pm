#
# PIR Actions.
#
# I'm not going to implement pure PASM grammar. Only PIR with full sugar
# for PCC, etc.

class PIR::Actions is HLL::Actions;

has $!BLOCK;
has $!MAIN;

has $!OPLIB;

INIT {
    pir::load_bytecode("nqp-setting.pbc");
}

method TOP($/) {
    make $<top>.ast;
}

method top($/) {
    my $past := POST::Node.new;
    for $<compilation_unit> {
        my $child := $_.ast;
        $past.push($child) if $child;
    }

    # Remember :main sub.
    $past<main_sub> := $!MAIN;

    make $past;
}

method compilation_unit:sym<.HLL> ($/) {
    our $*HLL := $<quote>.ast<value>;
}

method compilation_unit:sym<.namespace> ($/) {
    our $*NAMESPACE := $<namespace_key>[0] ?? $<namespace_key>[0].ast !! undef;
}

method newpad($/) { $!BLOCK := POST::Sub.new; }

method compilation_unit:sym<sub> ($/) {
    my $name := $<subname>.ast;
    $!BLOCK.name( $name );

    # TODO Handle pragmas.

    # TODO Handle :main pragma
    $!MAIN := $name unless $!MAIN;

    if $<statement> {
        for $<statement> {
            my $past := $_.ast;
            $!BLOCK.push( $past ) if $past;
        }
    }

    self.validate_labels($/, $!BLOCK);

    make $!BLOCK;
}

method param_decl($/) {
    my $name := ~$<name>;
    my $past := POST::Register.new(
        :name($name),
        :type(pir::substr__SSII(~$<pir_type>, 0, 1)),
        :declared(1),
    );

    if $!BLOCK.symbol($name) {
        $/.CURSOR.panic("Redeclaration of varaible '$name'");
    }

    if $<param_flag>[0] {
        $past.modifier( $<param_flag>[0].ast );
    }

    $!BLOCK.param($name, $past);
    $!BLOCK.symbol($name, $past);

    make $past;
}

method statement($/) {
    make $<pir_directive> ?? $<pir_directive>.ast !! $<labeled_instruction>.ast;
}

method labeled_instruction($/) {
    my $child := $<pir_instruction>[0] // $<op>[0]; # // $/.CURSOR.panic("NYI");
    my $past;
    $past := $child.ast if $child;

    # Create wrapping Label.
    my $label;
    if $<label>[0] {
        my $name := ~$<label>[0]<ident>;
        $label   := $!BLOCK.label($name);
        if pir::defined__IP($label) && $label.declared {
             $/.CURSOR.panic("Redeclaration of label '$name'");
        }

        $label := POST::Label.new(
            :name($name),
            :declared(1),
        );

        $!BLOCK.label($name, $label);

        $label.push($past) if $past;
        $past := $label;
    }

    make $past if $past;
}

method op($/) {
    my $past := POST::Op.new(
        :pirop(~$<name>),
    );

    # TODO Validate via OpLib
    my $oplib := self.oplib;
    my $op_family := $oplib.op_family(~$<name>);
    my $pirop     := $op_family.shift;

    if $<op_params>[0] {
        my $labels := pir::iter__PP($pirop.labels);
        for $<op_params>[0]<op_param> {
            my $label := pir::shift__IP($labels);
            if $label {
                my $name  := ~$_;
                my $label := POST::Label.new(:name($name));
                $!BLOCK.label($name, $label) unless $!BLOCK.label($name);
                $past.push($label);
            }
            else {
                $past.push( $_.ast );
            }
        }
    }

    self.validate_registers($/, $past);

    make $past;
}

method op_param($/) {
    make $<value> ?? $<value>.ast !! $<pir_key>.ast
}

method pir_directive:sym<.local>($/) {
    my $type := pir::substr__SSII(~$<pir_type>, 0, 1);
    for $<ident> {
        my $name := ~$_;
        if $!BLOCK.symbol($name) {
            $/.CURSOR.panic("Redeclaration of varaible '$name'");
        }

        my $past := POST::Register.new(
            :name($name),
            :type($type),
            :declared(1),
        );
        $!BLOCK.symbol($name, $past);
    }

}
#rule pir_directive:sym<.lex>        { <sym> <string_constant> ',' <pir_register> }
#rule pir_directive:sym<.file>       { <sym> <string_constant> }
#rule pir_directive:sym<.line>       { <sym> <int_constant> }
#rule pir_directive:sym<.annotate>   { <sym> <string_constant> ',' <constant> }
#rule pir_directive:sym<.include>    { <sym> <quote> }

# PCC
#rule pir_directive:sym<.begin_call>     { <sym> }
#rule pir_directive:sym<.end_call>       { <sym> }
#rule pir_directive:sym<.begin_return>   { <sym> }
#rule pir_directive:sym<.end_return>     { <sym> }
#rule pir_directive:sym<.begin_yield>    { <sym> }
#rule pir_directive:sym<.end_yield>      { <sym> }

#rule pir_directive:sym<.call>       { <sym> <value> [',' <continuation=pir_register> ]? }
#rule pir_directive:sym<.meth_call>  { <sym> <value> [',' <continuation=pir_register> ]? }
#rule pir_directive:sym<.nci_call>   { <sym> <value> [',' <continuation=pir_register> ]? }

#rule pir_directive:sym<.invocant>   { <sym> <value> }
#rule pir_directive:sym<.set_arg>    { <sym> <value> <arg_flag>* }
#rule pir_directive:sym<.set_return> { <sym> <value> <arg_flag>* }
#rule pir_directive:sym<.set_yield>  { <sym> <value> <arg_flag>* }
#rule pir_directive:sym<.get_result> { <sym> <value> <result_flag>* }

method pir_directive:sym<.return>($/) {
    my $past := POST::Call.new(
        :calltype('return'),
    );
    self.handle_pcc_args($/, $past);
    make $past;
}

method pir_directive:sym<.yield>($/) {
    my $past := POST::Call.new(
        :calltype('yield'),
    );
    self.handle_pcc_args($/, $past);
    make $past;
}


method pir_directive:sym<.tailcall>($/) {
    my $past := $<call>.ast;
    $past.calltype('tailcall');
    make $past;
}

method pir_directive:sym<.const>($/) {
    my $past := $<const_declaration>.ast;
    my $name := $past.name;
    if $!BLOCK.symbol($name) {
        $/.CURSOR.panic("Redeclaration of varaible '$name'");
    }
    $!BLOCK.symbol($name, $past);
}

#rule pir_directive:sym<.globalconst> { <sym> <const_declaration> }

method const_declaration:sym<int>($/) {
    my $past := $<int_constant>.ast;
    $past.name(~$<ident>);
    make $past;
}

method const_declaration:sym<num>($/) {
    my $past := $<float_constant>.ast;
    $past.name(~$<ident>);
    make $past;
}

method const_declaration:sym<string>($/) {
    my $past := $<string_constant>.ast;
    $past.name(~$<ident>);
    make $past;
}

# TODO Desugarize all of them.
method pir_instruction:sym<goto>($/) {
    make POST::Op.new(
        :pirop('branch'),
        POST::Label.new(
            :name(~$<ident>),
        ),
    );
}

method pir_instruction:sym<if>($/) {
    make POST::Op.new(
        :pirop('if'),
        $<variable>.ast,
        POST::Label.new(
            :name(~$<ident>),
        ),
    );
}

method pir_instruction:sym<unless>($/) {
    make POST::Op.new(
        :pirop('unless'),
        $<variable>.ast,
        POST::Label.new(
            :name(~$<ident>),
        ),
    );
}

method pir_instruction:sym<if_null>($/) {
    # TODO Check variable type for "p" or "s".
    make POST::Op.new(
        :pirop('if_null'),
        $<variable>.ast,
        POST::Label.new(
            :name(~$<ident>),
        ),
    );
}

method pir_instruction:sym<unless_null>($/) {
    # TODO Check variable type for "p" or "s".
    make POST::Op.new(
        :pirop('unless_null'),
        $<variable>.ast,
        POST::Label.new(
            :name(~$<ident>),
        ),
    );
}

method pir_instruction:sym<if_op>($/) {
    my $cmp_op;
    if    $<relop> eq '<=' { $cmp_op := 'le'; }
    elsif $<relop> eq '<'  { $cmp_op := 'lt'; }
    elsif $<relop> eq '==' { $cmp_op := 'eq'; }
    elsif $<relop> eq '!=' { $cmp_op := 'ne'; }
    elsif $<relop> eq '>'  { $cmp_op := 'gt'; }
    elsif $<relop> eq '>=' { $cmp_op := 'ge'; }
    else { $/.CURSOR.panic("Unhandled relative op $<relop>"); }

    make POST::Op.new(
        :pirop($cmp_op),
        $<lhs>.ast,
        $<rhs>.ast,
        POST::Label.new(
            :name(~$<ident>),
        ),
    );
}

method pir_instruction:sym<unless_op>($/) {
    my $cmp_op;
    # do the opposite of if_op
    if    $<relop> eq '<=' { $cmp_op := 'gt'; }
    elsif $<relop> eq '<'  { $cmp_op := 'ge'; }
    elsif $<relop> eq '==' { $cmp_op := 'ne'; }
    elsif $<relop> eq '!=' { $cmp_op := 'eq'; }
    elsif $<relop> eq '>'  { $cmp_op := 'le'; }
    elsif $<relop> eq '>=' { $cmp_op := 'lt'; }
    else { $/.CURSOR.panic("Unhandled relative op $<relop>"); }

    make POST::Op.new(
        :pirop($cmp_op),
        $<lhs>.ast,
        $<rhs>.ast,
        POST::Label.new(
            :name(~$<ident>),
        ),
    );
}

method pir_instruction:sym<assign>($/) {
    my $past;
    # It can be either assign to value or syntax sugar for something like "$I0 = err" op.
    my $variable := $<variable>.ast;
    my $value    := $<value>.ast;
    my $name     := ~$<value>;
    if $value.declared || $!BLOCK.symbol($name) {
        $past := POST::Op.new(
            :pirop('set'),
            $variable,
            $value,
        );
    }
    else {
        # Or it can be op.
        my $oplib := self.oplib;
        try {
            my $op    := $oplib{$name ~ '_' ~ $variable.type};
            $past := POST::Op.new(
                :pirop($name),
                $variable
            );
        }
    }

    unless $past {
        $/.CURSOR.panic("Register '" ~ $name ~ "' not predeclared");
    }

    make $past;
}

method pir_instruction:sym<op_assign_long_long_long_name>($/) {
    # TODO Check in OpLib for first argument. It should be "out" or "inout"
    my $past := POST::Op.new(
        :pirop(~$<op>),
        $<variable>.ast,
    );

    for $<op_params><op_param> {
        # Don't check "labels". We can't have them here.
        $past.push( $_.ast );
    }

    make $past;
}

method pir_instruction:sym<unary>($/) {
    my $op;
    if    $<unary> eq '!' { $op := 'not'; }
    elsif $<unary> eq '-' { $op := 'neg'; }
    #don't care about '~' for bnot
    else { $/.CURSOR.panic("Unhandled unary op $<unary>"); }

    make POST::Op.new(
        :pirop($op),
        $<variable>.ast,
        $<value>.ast,
    );
}

method pir_instruction:sym<binary_math>($/) {
    my $op;
    if    $<mathop> eq '+'   { $op := 'add'; }
    elsif $<mathop> eq '-'   { $op := 'sub'; }
    elsif $<mathop> eq '**'  { $op := 'pow'; } #parrot may not generate pow_x_x_x
    elsif $<mathop> eq '/'   { $op := 'div'; }
    elsif $<mathop> eq '%'   { $op := 'mod'; }
    elsif $<mathop> eq '*'   { $op := 'mul'; }
    elsif $<mathop> eq '.'   { $op := 'concat'; } #TODO: strings only
    elsif $<mathop> eq '>>>' { $op := 'lsr'; }
    elsif $<mathop> eq '<<'  { $op := 'shl'; }
    elsif $<mathop> eq '>>'  { $op := 'shr'; }
    elsif $<mathop> eq '&&'  { $op := 'and'; }
    elsif $<mathop> eq '||'  { $op := 'or'; }
    elsif $<mathop> eq '~~'  { $op := 'xor'; }
    elsif $<mathop> eq '&'   { $op := 'band'; }
    elsif $<mathop> eq '|'   { $op := 'bor'; }
    elsif $<mathop> eq '~'   { $op := 'bxor'; }
    else { $/.CURSOR.panic("Unhandled binary math op $<mathop>"); }

    make POST::Op.new(
        :pirop($op),
        $<variable>.ast,
        $<lhs>.ast,
        $<rhs>.ast,
    );
}

method pir_instruction:sym<binary_logic>($/) {
    my $cmp_op;
    if    $<relop> eq '<=' { $cmp_op := 'isle'; }
    elsif $<relop> eq '<'  { $cmp_op := 'islt'; }
    elsif $<relop> eq '==' { $cmp_op := 'iseq'; }
    elsif $<relop> eq '!=' { $cmp_op := 'isne'; }
    elsif $<relop> eq '>'  { $cmp_op := 'isgt'; }
    elsif $<relop> eq '>=' { $cmp_op := 'isge'; }
    else { $/.CURSOR.panic("Unhandled relative op $<relop>"); }

    make POST::Op.new(
        :pirop($cmp_op),
        $<variable>.ast,
        $<lhs>.ast,
        $<rhs>.ast,
    );
}



method pir_instruction:sym<call>($/) { make $<call>.ast; }

method pir_instruction:sym<call_assign>($/) {
    my $past := self.pir_instruction:sym<call>($/);

    # Store params (if any)
    my $results := POST::Node.new;
    $results.push( $<variable>.ast );
    self.validate_registers($/, $results);
    $past.results($results);

    make $past;
}

method pir_instruction:sym<call_assign_many>($/) {
    my $past := self.pir_instruction:sym<call>($/);

    # Store params (if any)
    if $<results>[0] {
        my $results := POST::Node.new;
        for $<results>[0]<result> {
            $results.push( $_.ast );
        }
        self.validate_registers($/, $results);
        $past.results($results);
    }

    make $past;
}


# Short PCC call.
#proto regex call { <...> }
method call:sym<pmc>($/) {
    my $past := POST::Call.new(
        :calltype('call'),
        :name($<variable>.ast),
    );
    self.handle_pcc_args($/, $past);
    make $past;
}

method call:sym<sub>($/) {
    # We need register to store Sub PMC. Either constant or from find_sub_not_null
    $!BLOCK.symbol('!SUB', POST::Register.new(:name('!SUB'), :type('p')));

    my $past := POST::Call.new(
        :calltype('call'),
        :name($<quote>.ast),
    );
    self.handle_pcc_args($/, $past);
    make $past;
}

method call:sym<dynamic>($/) {
    my $past := self.call:sym<pmc>($/);
    $past.invocant($<invocant>.ast);
    make $past;
}

method call:sym<method>($/) {
    my $past := POST::Call.new(
        :calltype('call'),
        :name($<quote>.ast),
    );
    self.handle_pcc_args($/, $past);
    $past.invocant($<invocant>.ast);
    make $past;
}

method handle_pcc_args($/, $past) {
    if $<args>[0] {
        # Store params (if any)
        my $params := POST::Node.new;
        for $<args>[0]<arg> {
            $params.push( $_.ast );
        }
        self.validate_registers($/, $params);

        $past.params($params);
    }
}

#rule args { <arg> ** ',' }

#rule arg {
#    | <quote> '=>' <value>
#    | <value> <arg_flag>*
#}

method arg($/) {
    # TODO Handle flags, fatarrow
    make $<value>.ast;
}

method result($/) {
    # TODO Handle flags
    make $<variable>.ast;
}

method param_flag:sym<:call_sig>($/)        { make 'call_sig' }
method param_flag:sym<:slurpy>($/)          { make 'slurpy'   }
method param_flag:sym<slurpy named>($/)     { make 'slurpy named' }
method param_flag:sym<:optional>($/)        { make 'optional' }
method param_flag:sym<:opt_flag>($/)        { make 'opt_flag' }
method param_flag:sym<named_flag>($/)       {
    make hash( named => $<quote> ?? dequote(~$<quote>.ast) !! undef )
}

method value($/) { make $<constant> ?? $<constant>.ast !! $<variable>.ast }

method constant($/) {
    my $past;
    if $<int_constant> {
        $past := $<int_constant>.ast;
    }
    elsif $<float_constant> {
        $past := $<float_constant>.ast;
    }
    else {
        $past := $<string_constant>.ast;
    }
    make $past;
}

method int_constant($/) {
    make POST::Constant.new(
        :type<ic>,
        :value(~$/),
    );
}

method float_constant($/) {
    make POST::Constant.new(
        :type<nc>,
        :value(~$/),
    );
}

method string_constant($/) {
    make POST::Constant.new(
        :type<sc>,
        :value($<quote>.ast<value>),
    );
}

method variable($/) {
    my $past;
    if $<ident> {
        # Named register
        $past := POST::Value.new(
            :name(~$<ident>),
        );
    }
    else {
        # Numbered register
        my $type := ~$<pir_register><INSP>;
        my $name := '$' ~ $type ~ ~$<pir_register><reg_number>;
        $type := pir::downcase__SS($type);
        $past := POST::Value.new(
            :name($name),
            :type($type),
        );

        # Register it in symtable right now to simplify check in validate_registers
        $!BLOCK.symbol($name, POST::Register.new(
            :name($name),
            :type($type),
        ));
    }

    make $past;
}

method subname($/) {
    make $<ident> ?? ~$<ident> !! ~($<quote>.ast<value>);
}

method quote:sym<apos>($/) {
    make POST::Constant.new(
        :type("sc"),
        :value(dequote(~$/))
    );
}

method quote:sym<dblq>($/) {
    make POST::Constant.new(
        :type("sc"),
        :value(dequote(~$/))
    );
}


method validate_registers($/, $node) {
    for @($node) {
        self.validate_register($/, $_);
    }
}

our multi method validate_register($/, POST::Value $reg) {
    my $name := $reg.name;
    if $name && !$!BLOCK.symbol($name) {
        $/.CURSOR.panic("Register '" ~ $name ~ "' not predeclared");
    }
}

# POST::Label, POST::Constant
our multi method validate_register($/, $arg) { }

method validate_labels($/, $node) {
    for $node.labels {
        unless $_.value.declared {
            $/.CURSOR.panic("Label '" ~ $_.value.name ~ "' not declared");
        }
    }
}

sub dequote($a) {
    my $l := pir::length__IS($a);
    pir::substr__SSII($a, 1, $l-2);
}

method oplib() {
    $!OPLIB := pir::new__ps('OpLib') unless pir::defined__ip($!OPLIB);
    $!OPLIB;
}

# vim: ft=perl6
