package HTML::Zoom::StreamBase;

use strict;
use warnings FATAL => 'all';

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

sub flatten {
  my $source_stream = shift;
  require HTML::Zoom::CodeStream;
  my $cur_stream;
  HTML::Zoom::CodeStream->new({
    code => sub {
      return unless $source_stream;
      my $next;
      until (($next) = ($cur_stream ? $cur_stream->next : ())) {
#::Dwarn $source_stream;
        unless (($cur_stream) = $source_stream->next) {
          undef $source_stream; return;
        }
      }
#::Dwarn $next;
      return $next;
    }
  });
}

sub map {
  my ($source_stream, $map_func) = @_;
  require HTML::Zoom::CodeStream;
  HTML::Zoom::CodeStream->new({
    code => sub {
      return unless $source_stream;
      # If we were aiming for a "true" perl-like map then we should
      # elegantly handle the case where the map function returns 0 events
      # and the case where it returns >1 - if you're reading this comment
      # because you wanted it to do that, now would be the time to fix it :)
      if (my ($next) = $source_stream->next) {
        #### XXXX collapsing this into a return doesn't work. what the
        #### flying fornication ... -- mst
        my $mapped = do { local $_ = $next; $map_func->($next) };
        return $mapped;
      }
      undef $source_stream; return;
    }
  });
}

1;
