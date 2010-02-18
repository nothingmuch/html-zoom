package HTML::Zoom::StreamUtils;

use strict;
use warnings FATAL => 'all';
use base qw(HTML::Zoom::SubObject);

use HTML::Zoom::CodeStream;
use HTML::Zoom::FilterStream;

sub stream_from_code {
  my ($self, $code) = @_;
  HTML::Zoom::CodeStream->new({
    code => $code,
    zconfig => $self->_zconfig,
  })
}

sub stream_from_array {
  my $self = shift;
  my @array = @_;
  $self->stream_from_code(sub {
    return unless @array;
    return shift @array;
  });
}

sub stream_concat {
  shift->stream_from_array(@_)->flatten;
}

sub stream_from_proto {
  my ($self, $proto) = @_;
  my $ref = ref $proto;
  if (not $ref) {
    return $self->stream_from_array({
      type => 'TEXT',
      raw => $self->_zconfig->parser->html_escape($proto)
    });
  } elsif ($ref eq 'ARRAY') {
    return $self->stream_from_array(@$proto);
  } elsif ($ref eq 'CODE') {
    return $proto->();
  } elsif ($ref eq 'SCALAR') {
    return $self->_zconfig->parser->html_to_stream($$proto);
  }
  die "Don't know how to turn $proto (ref $ref) into a stream";
}

sub wrap_with_filter {
  my ($self, $stream, $match, $filter) = @_;
  HTML::Zoom::FilterStream->new({
    stream => $stream,
    match => $match,
    filter => $filter,
    zconfig => $self->_zconfig,
  })
}

1;
