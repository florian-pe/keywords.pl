# keywords.pl

This script is a refactor of `Devel::Tokenizer::C` into a more functional style. It takes as argument a file containing a list of keywords and generates an efficient lexer function for recognizing those keywords.

The current list of keywords in keywords.txt has been extracted from the `Perl/perl5` repository from the file `regen/keywords.pl`.

```
./keywords.pl keywords.txt > lexer_keywords.c
gcc -c lexer_keywords.c -o lexer_keywords.o
```


