package HTML::Zoom::CodeStream;

use strict;
use warnings FATAL => 'all';
use base qw(HTML::Zoom::StreamBase);

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

sub peek {
  my ($self) = @_;
  if (exists $self->{_peeked}) {
    return ($self->{_peeked});
  }
  if (my ($peeked) = $self->next) {
    return ($self->{_peeked} = $peeked);
  }
  return;
}

sub next {
  my ($self) = @_;

  # peeked entry so return that

  if (exists $self->{_peeked}) {
    return (delete $self->{_peeked});
  }

  $self->{_code}->();
}

1;

