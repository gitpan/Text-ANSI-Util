package Text::ANSI::Util;

use 5.010001;
use locale;
use strict;
use utf8;
use warnings;

use List::Util qw(max);
use Text::CharWidth qw(mbswidth);
use Text::WideChar::Util qw(mbtrunc);

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
                       ta_detect
                       ta_length
                       ta_mbpad
                       ta_mbswidth
                       ta_mbswidth_height
                       ta_mbtrunc
                       ta_mbwrap
                       ta_pad
                       ta_split_codes
                       ta_strip
                       ta_trunc
                       ta_wrap
               );

our $VERSION = '0.06'; # VERSION

# used to find/strip escape codes from string
our $re       = qr/
                      #\x1b\[ (?: (\d+) ((?:;[^;]+?)*) )? ([\x40-\x7e])
                      # without captures
                      \x1b\[ (?: \d+ (?:;[^;]+?)* )? [\x40-\x7e]
                  /osx;

# used to split into words
our $re_words = qr/
                      (?:
                          \S+ |
                          \x1b\[ (?: \d+ (?:;[^;]+?)*)? [\x40-\x7e]
                      )+

                  |

                      \s+
                  /osx;

sub ta_detect {
    my $text = shift;
    $text =~ $re ? 1:0;
}

sub ta_length {
    my $text = shift;
    length(ta_strip($text));
}

sub ta_strip {
    my $text = shift;
    $text =~ s/$re//og;
    $text;
}

sub ta_split_codes {
    my ($text, $mark) = @_;
    if ($mark) {
        return map {[$_, $re ? 1:0]} split(/((?:$re)+)/, $text);
    } else {
        return split(/((?:$re)+)/, $text);
    }
}

sub ta_mbswidth_height {
    my $text = shift;
    my $num_lines = 0;
    my @lens;
    for my $e (split /(\r?\n)/, ta_strip($text)) {
        if ($e =~ /\n/) {
            $num_lines++;
            next;
        }
        $num_lines = 1 if $num_lines == 0;
        push @lens, mbswidth($e);
    }
    [max(@lens) // 0, $num_lines];
}

# same like _ta_mbswidth, but without handling multiline text
sub _ta_mbswidth0 {
    my $text = shift;
    mbswidth(ta_strip($text));
}

sub ta_mbswidth {
    my $text = shift;
    ta_mbswidth_height($text)->[0];
}

sub _ta_wrap {
    my ($is_mb, $text, $width) = @_;
    $width //= 80;

    my @res;
    my @p = $text =~ /($re_words)/g;
    #use Data::Dump; dd \@p;
    my $col = 0;
    my $i = 0;
    while (my $p = shift(@p)) {
        $i++;
        my $num_nl = 0;
        my $is_pb; # paragraph break
        my $is_ws;
        my $w;
        #say "D:col=$col, p=[$p]";
        if ($p =~ /\A\s/s) {
            $is_ws++;
            $num_nl++ while $p =~ s/\r?\n//;
            if ($num_nl >= 2) {
                $is_pb++;
                $w = 0;
            } else {
                $p = " ";
                $w = 1;
            }
        } else {
            if ($is_mb) {
                $w = _ta_mbswidth0($p);
            } else {
                $w = ta_length($p);
            }
        }
        $col += $w;
        #say "D:col=$col, is_pb=${\($is_pb//0)}, is_ws=${\($is_ws//0)}, num_nl=$num_nl";

        if ($is_pb) {
            push @res, "\n" x $num_nl;
            $col = 0;
        } elsif ($col > $width+1) {
            # remove space at the end of prev line
            if (@res && $res[-1] eq ' ') {
                pop @res;
            }

            push @res, "\n";
            if ($is_ws) {
                $col = 0;
            } else {
                push @res, $p;
                $col = $w;
            }
        } else {
            # remove space at the end of text
            if (@p || !$is_ws) {
                push @res, $p;
            } else {
                if ($num_nl == 1) {
                    push @res, "\n";
                }
            }
        }
    }
    join "", @res;
}

sub ta_wrap {
    _ta_wrap(0, @_);
}

sub ta_mbwrap {
    _ta_wrap(1, @_);
}

sub _ta_pad {
    my ($is_mb, $text, $width, $which, $padchar, $is_trunc) = @_;
    if ($which) {
        $which = substr($which, 0, 1);
    } else {
        $which = "r";
    }
    $padchar //= " ";

    my $w = $is_mb ? _ta_mbswidth0($text) : ta_length($text);
    if ($is_trunc && $w > $width) {
        my $res = $is_mb ?
            ta_mbtrunc($text, $width, 1) : ta_trunc($text, $width, 1);
        $text = $res->[0] . ($padchar x ($width-$res->[1]));
    } else {
        if ($which eq 'l') {
            $text = ($padchar x ($width-$w)) . $text;
        } elsif ($which eq 'c') {
            my $n = int(($width-$w)/2);
            $text = ($padchar x $n) . $text . ($padchar x ($width-$w-$n));
        } else {
            $text .= ($padchar x ($width-$w));
        }
    }
    $text;
}

sub ta_pad {
    _ta_pad(0, @_);
}

sub ta_mbpad {
    _ta_pad(1, @_);
}

sub _ta_trunc {
    my ($is_mb, $text, $width, $return_width) = @_;

    my $w = $is_mb ? _ta_mbswidth0($text) : ta_length($text);
    return $text if $w <= $width;
    my @p = ta_split_codes($text);
    my @res;
    my $append = 1; # whether we should add more text
    $w = 0;
    while (my ($t, $ansi) = splice @p, 0, 2) {
        if ($append) {
            my $tw = $is_mb ? mbswidth($t) : length($t);
            if ($w+$tw <= $width) {
                push @res, $t;
                $w += $tw;
                $append = 0 if $w == $width;
            } else {
                my $tres = $is_mb ?
                    mbtrunc($t, $width-$w, 1) :
                        [substr($t, 0, $width-$w), $width-$w];
                push @res, $tres->[0];
                $w += $tres->[1];
                $append = 0;
            }
        }
        push @res, $ansi if defined($ansi);
    }

    if ($return_width) {
        return [join("", @res), $w];
    } else {
        return join("", @res);
    }
}

sub ta_trunc {
    _ta_trunc(0, @_);
}

sub ta_mbtrunc {
    _ta_trunc(1, @_);
}

1;
# ABSTRACT: Routines for text containing ANSI escape codes


__END__
=pod

=head1 NAME

Text::ANSI::Util - Routines for text containing ANSI escape codes

=head1 VERSION

version 0.06

=head1 SYNOPSIS

 use Text::ANSI::Util qw(
     ta_detect ta_length ta_mbpad ta_mbswidth ta_mbswidth_height ta_mbwrap
     ta_pad ta_strip ta_wrap);

 # detect whether text has ANSI escape codes?
 say ta_detect("red");         # => false
 say ta_detect("\x1b[31mred"); # => true

 # calculate length of text (excluding the ANSI escape codes)
 say ta_length("red");         # => 3
 say ta_length("\x1b[31mred"); # => 3

 # calculate visual width of text if printed on terminal (can handle Unicode
 # wide characters and exclude the ANSI escape codes)
 say ta_mbswidth("\x1b[31mred"); # => 3
 say ta_mbswidth("\x1b[31m红色"); # => 4

 # ditto, but also return the number of lines
 say ta_mbswidth_height("\x1b[31mred\n红色"); # => [4, 2]

 # strip ANSI escape codes
 say ta_strip("\x1b[31mred"); # => "red"

 # split codes (ANSI codes are always on the even positions)
 my @parts = ta_split_codes("\x1b[31mred"); # => ("", "\x1b[31m", "red")

 # wrap text to a certain column width, handle ANSI escape codes
 say ta_wrap("....", 40);

 # ditto, but handle wide characters
 say ta_mbwrap(...);

 # pad (left, right, center) text to a certain width, handles multiple lines
 say ta_pad("foo", 10);                          # => "foo       "
 say ta_pad("foo", 10, "left");                  # => "       foo"
 say ta_pad("foo\nbarbaz\n", 10, "center", "."); # => "...foo....\n..barbaz..\n"

 # ditto, but handle wide characters
 say ta_mbpad(...);

 # truncate text to a certain width while still passing ANSI escape codes
 use Term::ANSIColor;
 my $text = color("red")."red text".color("reset"); # => "\e[31mred text\e[0m"
 say ta_trunc($text, 5);           # => "\e[31mred t\e[0m"

 # ditto, but handle wide characters
 say ta_mbtrunc(...);

=head1 DESCRIPTION

This module provides routines for dealing with text containing ANSI escape codes
(mainly ANSI color codes).

Current caveats:

=over

=item * All codes are assumed to have zero width

This is true for color codes and some other codes, but there are also codes to
alter cursor positions which means they can have negative or undefined width.

=item * Single-character CSI (control sequence introducer) currently ignored

Only C<ESC+[> (two-character CSI) is currently parsed.

BTW, in ASCII terminals, single-character CSI is C<0x9b>. In UTF-8 terminals, it
is C<0xc2, 0x9b> (2 bytes).

=item * Private-mode- and trailing-intermediate character currently not parsed

=back

=head1 FUNCTIONS

=head2 ta_detect($text) => BOOL

Return true if C<$text> contains ANSI escape codes, false otherwise.

=head2 ta_length($text) => INT

Count the number of bytes in $text, while ignoring ANSI escape codes. Equivalent
to C<< length(ta_strip($text) >>. See also: ta_mbswidth().

=head2 ta_mbswidth($text) => INT

Return visual width of C<$text> (in number of columns) if printed on terminal.
Equivalent to C<< Text::CharWidth::mbswidth(ta_strip($text)) >>. This function
can be used e.g. in making sure that your text aligns vertically when output to
the terminal in tabular/table format.

Note: C<mbswidth()> handles C<\0> correctly (regard it as having zero width) but
currently does not handle control characters like C<\n>, C<\t>, C<\b>, C<\r>,
etc well (they are just counted as having -1). So make sure that your text does
not contain those characters.

But at least ta_mbswidth() handles multiline text correctly, e.g.: C<<
ta_mbswidth("foo\nbarbaz") >> gives 6 instead of 3-1+8 = 8. It splits the input
text first against C<< /\r?\n/ >>.

=head2 ta_mbswidth_height($text) => [INT, INT]

Like ta_mbswidth(), but also gives height (number of lines). For example, C<<
ta_mbswidth_height("foobar\nb\n") >> gives [6, 3].

=head2 ta_strip($text) => STR

Strip ANSI escape codes from C<$text>, returning the stripped text.

=head2 ta_split_codes($text) => LIST

Split C<$text> to a list containing alternating ANSI escape codes and text. ANSI
escape codes are always on the second element, fourth, and so on. Example:

 ta_split_codes("");              # => ()
 ta_split_codes("a");             # => ("a")
 ta_split_codes("a\e[31m");       # => ("a", "\e[31m")
 ta_split_codes("\e[31ma");       # => ("", "\e[31m", "a")
 ta_split_codes("\e[31ma\e[0m");  # => ("", "\e[31m", "a", "\e[0m")
 ta_split_codes("\e[31ma\e[0mb"); # => ("", "\e[31m", "a", "\e[0m", "b")
 ta_split_codes("\e[31m\e[0mb");  # => ("", "\e[31m\e[0m", "b")

so you can do something like:

 my @parts = ta_split_codes($text);
 while (my ($text, $ansicode) = splice(@parts, 0, 2)) {
     ...
 }

=head2 ta_wrap($text, $width) => STR

Wrap C<$text> to C<$width> columns.

C<$width> defaults to 80 if not specified.

Note: currently performance is rather abysmal (~ 1200/s on my Core i5-2400
3.1GHz desktop for a ~ 1KB of text), so call this routine sparingly ;-).

=head2 ta_mbwrap($text, $width) => STR

Like ta_wrap(), but it uses ta_mbswidth() instead of ta_length(), so it can
handle wide characters.

Note: for text which does not have whitespaces between words, like Chinese, you
will have to separate the words first (e.g. using L<Lingua::ZH::WordSegmenter>).
The module also currently does not handle whitespace-like characters other than
ASCII 32 (for example, the Chinese dot 。).

Note: currently performance is rather abysmal (~ 1000/s on my Core i5-2400
3.1GHz desktop for a ~ 1KB of text), so call this routine sparingly ;-).

=head2 ta_pad($text, $width[, $which[, $padchar[, $truncate]]]) => STR

Return C<$text> padded with C<$padchar> to C<$width> columns. C<$which> is
either "r" or "right" for padding on the right (the default if not specified),
"l" or "left" for padding on the right, or "c" or "center" or "centre" for
left+right padding to center the text.

C<$padchar> is whitespace if not specified. It should be string having the width
of 1 column.

Does *not* handle multiline text; you can split text by C</\r?\n/> yourself.

=head2 ta_mbpad => STR

Like ta_pad() but it uses ta_mbswidth() instead of ta_length(), so it can handle
wide characters.

=head2 ta_trunc($text, $width) => STR

Truncate C<$text> to C<$width> columns while still including all the ANSI escape
codes. This ensures that truncated text still reset colors, etc.

Does *not* handle multiline text; you can split text by C</\r?\n/> yourself.

=head2 ta_mbtrunc($text, $width) => STR

Like ta_trunc() but it uses ta_mbswidth() instead of ta_length(), so it can
handle wide characters.

=head1 FAQ

=head2 How do I truncate string based on number of characters?

You can simply use Perl's ta_trunc() even on text containing wide characters.
ta_trunc() uses Perl's length() which works on a per-character basis.

=head1 TODOS

=over

=back

=head1 SEE ALSO

L<Term::ANSIColor>

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
