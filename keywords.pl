#!/usr/bin/perl

use strict;
use warnings;
use v5.10;

sub group_by {
    my $code = shift;
    my %output;
    local $_;

    while (@_) {
        $_ = shift;
        push $output{$code->()}->@*, $_;
    }
    %output;
}

sub stringify;

sub make_lexer {
    my %arg = @_;
    my %by_length = group_by sub { length }, $arg{keywords}->@*;

    stringify 0, ["switch", $arg{variable_length},
        (map {
            my $length = $_;
            my $count = $by_length{$length}->@*;

            my $plural_mark = $count > 1 ? "s" : "";
            ["comment", "$count keyword$plural_mark of length $length"],

            ["case", $length,
                make_ast_trie(
                    keywords        => $by_length{$length},
                    character_order => $arg{character_order},
                    variable_token  => $arg{variable_token},
                )
            ]
        }
        sort { $a <=> $b } keys %by_length),

        ["default",
            ["goto", "unrecognized"]
        ]
    ]
}



sub make_ast_trie {
    my %arg = @_;
    my $order = $arg{character_order};
    my @keywords = $arg{keywords}->@*;
    my $var_token = $arg{variable_token};
    my $ast = [];
    my $ptr;

    my @histogram;
    for my $keyword (@keywords) {

        for (my $pos = 0; $pos < length $keyword; $pos++){

            my $char = substr($keyword, $pos, 1);
            $histogram[$pos]{$char}++;
        }
    }

    my @pos_order;
    if ($order eq "incremental") {
        @pos_order = 0 .. $#histogram;
    }
    elsif ($order eq "least_common_first") {
        @pos_order = sort { $histogram[$a]->%* <=> $histogram[$b]->%* } 0 .. $#histogram;
    }
    elsif ($order eq "most_common_first") {
        @pos_order = sort { $histogram[$b]->%* <=> $histogram[$a]->%* } 0 .. $#histogram;
    }   
    else {
        say STDERR "character_order '$order' not recognized";
        exit 1;
    }

    for my $keyword (@keywords) { 

        my @chars = split //, $keyword;
        my @comparison_order = map { { pos => $_, char => "'$chars[$_]'" } } @pos_order;

        $ptr = $ast;

        COMPARISON:
        for my $comp (@comparison_order) {

            if ($ptr->@* == 0) {
                $ptr->@* =
                ("if", ["==", $comp->{pos}, $comp->{char}],
                    []
                );
                $ptr = $ptr->[2];
            }
            elsif ($ptr->[0] eq "if") {
                if ($ptr->[1][2] eq $comp->{char}) {
                    $ptr = $ptr->[2];
                }
                else {
                    $ptr->@* =
                    ("switch", "$var_token\[$comp->{pos}]",
                        ["case", $ptr->[1][2],
                            $ptr->[2]
                        ],
                        ["case", $comp->{char},
                            []
                        ],
                    );
                    $ptr = $ptr->[-1][2];
                }
            }
            elsif ($ptr->[0] eq "switch") {

                for my $case ($ptr->@[2 .. $ptr->$#*]) {

                    if ($case->[1] eq $comp->{char}) {
                        $ptr = $case->[2];
                        next COMPARISON;
                    }
                }

                push $ptr->@*,
                ["case", $comp->{char},
                    []
                ];

                $ptr = $ptr->[-1][2];
            }
        }

        $ptr->@* = ("return", "TOKEN_$keyword");
    }

    my $ast_walk;
    $ast_walk = sub {
        my ($ast, $code) = @_;
        
        while ($code->($ast)) {
            1;
        }
        return if !defined $ast;
        return if $ast->@* == 0;

        if ($ast->[0] eq "if") {
            $ast_walk->($ast->[2], $code);
        }
        elsif ($ast->[0] eq "switch") {
            for (my $i=2; $i < $ast->@*; $i++) {

                next if $ast->[$i][0] ne "case"; # could be a "comment"
                $ast_walk->($ast->[$i][2], $code);
            }
        }
    };

    $ast_walk->($ast, sub {
        my $ast = shift;

        return if !defined $ast;
        return if $ast->@* == 0;

        if ($ast->[0] eq "if" && $ast->[2][0] eq "if") {

            my $cond_1 = $ast->[1];
            my $cond_2 = $ast->[2][1];

            my $cond_merged = ["&&"];
            push $cond_merged->@*, ($cond_1->[0] eq "==" ? $cond_1 : $cond_1->@[1 .. $cond_1->$#*]);
            push $cond_merged->@*, ($cond_2->[0] eq "==" ? $cond_2 : $cond_2->@[1 .. $cond_2->$#*]);

            $ast->@* = ("if", $cond_merged, $ast->[2][2]);

            return 1;
        }
        else {
            return 0;
        }
    });

    $ast_walk->($ast, sub {
        my $ast = shift;

        return if !defined $ast;
        return if $ast->@* == 0;

        if ($ast->[0] eq "if" && $ast->[1][0] eq "==" && $ast->@* == 3) {

            my $pos = $ast->[1][1];
            $ast->[1][1] = "$var_token\[$pos]";
            push $ast->@*, ["goto", "unrecognized"];
            return 1;
        }
        elsif ($ast->[0] eq "if" && $ast->[1][0] eq "&&" && $ast->@* == 3) {

            for (my $i = 1; $i < $ast->[1]->@*; $i++) {

                my $pos = $ast->[1][$i][1];
                $ast->[1][$i][1] = "$var_token\[$pos]";
            }
            push $ast->@*, ["goto", "unrecognized"];
            return 1;
        }
        elsif ($ast->[0] eq "switch" && $ast->[-1][0] ne "default") {

            push $ast->@*,
            ["default",
                ["goto", "unrecognized"]
            ];
            return 1;
        }
        else {
            return 0;
        }
    });

    $ast
}

sub stringify {
    my ($level, $ast) = @_;
    my $indent = "  " x ($level);

    if ($ast->[0] eq "comment") {
        "/* $ast->[1] */"
    }
    elsif ($ast->[0] eq "goto") {
        "goto $ast->[1];\n"
    }
    elsif ($ast->[0] eq "return") {
        "return $ast->[1];\n"
    }
    elsif ($ast->[0] eq "case") {
        "case $ast->[1]: {\n"
        . stringify($level+1, $ast->[2]) =~ s/^/  /gmr
        . "}\n"
    }
    elsif ($ast->[0] eq "default") {
        "default: {\n"
        . stringify($level+1, $ast->[1]) =~ s/^/  /gmr
        . "}\n"
    }
    elsif ($ast->[0] eq "if") {
        my $cond;
        if ($ast->[1][0] eq "==") {
            $cond = "$ast->[1][1] == $ast->[1][2]";
        }
        elsif ($ast->[1][0] eq "&&") {

            $cond =
            "$ast->[1][1][1] == $ast->[1][1][2] &&\n"
            . join(" &&\n",
                map { "    $_->[1] == $_->[2]" } $ast->[1]->@[2 .. $ast->[1]->$#*]
            ) . "\n";
        }

          "if ($cond) {\n"
        .    (stringify($level+1, $ast->[2]) =~ s/^/  /gmr)
        . "}\n\n"
        . stringify($level, $ast->[3]);
    }
    elsif ($ast->[0] eq "switch") {
        ("switch ($ast->[1]) {\n"
        . join ("\n",
            map {
                stringify($level+1, $_) =~ s/^/  /gmr
            } $ast->@[2 .. $ast->$#*]
          )
        . "}\n")
    }
    else {
        die
    }
}


my @keywords;
my $keyword_num = 0;

while (<>) {
    chomp;
    my $keyword = $_;
    push @keywords, $keyword;
    printf "%-31s %d\n", "#define TOKEN_$keyword", $keyword_num;
    $keyword_num++;
}


my $switch = make_lexer(
    keywords        => \@keywords,
    character_order => "incremental",
#   character_order => "least_common_first",
#   character_order => "most_common_first",
    variable_length => "length",
    variable_token  => "input",
) =~ s/^/  /gmr;


say <<"EOF";


int lex_keyword(char *input, int length) {
$switch
unrecognized:
  return 0;
}

EOF




