package HTML::Zoom::CodeStream;

use strict;
use warnings FATAL => 'all';

sub from_array {
  my ($class, @array) = @_;
  $class->new({ code => sub {
    return unless @array;
    return shift @array;
  }});
}

sub new {
  my ($class, $args) = @_;
  bless({ _code => $args->{code} }, $class);
}

sub next {
  $_[0]->{_code}->()
}

1;

