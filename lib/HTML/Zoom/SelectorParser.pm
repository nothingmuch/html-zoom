package HTML::Zoom::SelectorParser;

use strict;
use warnings FATAL => 'all';
use base qw(HTML::Zoom::SubObject);
use Carp qw(confess);

my $sel_char = '-\w_';
my $sel_re = qr/([$sel_char]+)/;

sub new { bless({}, shift) }

sub _raw_parse_simple_selector {
  for ($_[1]) { # same pos() as outside

    # '*' - match anything

    /\G\*/gc and
      return sub { 1 };

    # 'element' - match on tag name

    /\G$sel_re/gc and
      return do {
        my $name = $1;
        sub { $_[0]->{name} && $_[0]->{name} eq $name }
      };

    # '#id' - match on id attribute

    /\G#$sel_re/gc and
      return do {
        my $id = $1;
        sub { $_[0]->{attrs}{id} && $_[0]->{attrs}{id} eq $id }
      };

    # '.class1.class2' - match on intersection of classes

    /\G((?:\.$sel_re)+)/gc and
      return do {
        my $cls = $1; $cls =~ s/^\.//;
        my @cl = split(/\./, $cls);
        sub {
          $_[0]->{attrs}{class}
          && !grep $_[0]->{attrs}{class} !~ /(^|\s+)$_($|\s+)/, @cl
        }
      };

    confess "Couldn't parse $_ as starting with simple selector";
  }
}

sub parse_selector {
  my $self = $_[0];
  my $sel = $_[1]; # my pos() only please
  die "No selector provided" unless $sel;
  local *_;
  for ($sel) {
    my @sub;
    PARSE: { do {
      push(@sub, $self->_raw_parse_simple_selector($_));
      last PARSE if (pos == length);
      /\G\s*,\s*/gc or confess "Selectors not comma separated";
    } until (pos == length) };
    return $sub[0] if (@sub == 1);
    return sub {
      foreach my $inner (@sub) {
        if (my $r = $inner->(@_)) { return $r }
      }
    };
  }
} 
  

1;
