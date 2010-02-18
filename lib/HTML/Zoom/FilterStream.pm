package HTML::Zoom::FilterStream;

use strict;
use warnings FATAL => 'all';
use base qw(HTML::Zoom::StreamBase);

sub new {
  my ($class, $args) = @_;
  bless(
    {
      _stream => $args->{stream},
      _match => $args->{match},
      _filter => $args->{filter},
      _zconfig => $args->{zconfig},
    },
    $class
  );
}

sub next {
  my ($self) = @_;

  # peeked entry so return that

  if (exists $self->{_peeked}) {
    return (delete $self->{_peeked});
  }

  # if our main stream is already gone then we can short-circuit
  # straight out - there's no way for an alternate stream to be there

  return unless $self->{_stream};

  # if we have an alternate stream (provided by a filter call resulting
  # from a match on the main stream) then we want to read from that until
  # it's gone - we're still effectively "in the match" but this is the
  # point at which that fact is abstracted away from downstream consumers

  if (my $alt = $self->{_alt_stream}) {

    if (my ($evt) = $alt->next) {
      return $evt;
    }

    # once the alternate stream is exhausted we can throw it away so future
    # requests fall straight through to the main stream

    delete $self->{_alt_stream};
  }

  # if there's no alternate stream currently, process the main stream

  while (my ($evt) = $self->{_stream}->next) {

    # don't match this event? return it immediately

    return $evt unless $evt->{type} eq 'OPEN' and $self->{_match}->($evt);

    # run our filter routine against the current event

    my ($res) = $self->{_filter}->($evt, $self->{_stream});

    # if the result is just an event, we can return that now

    return $res if ref($res) eq 'HASH';

    # if no result at all, jump back to the top of the loop to get the
    # next event and try again - the filter has eaten this one

    next unless defined $res;

    # ARRAY means a pair of [ $evt, $new_stream ]

    if (ref($res) eq 'ARRAY') {
      $self->{_alt_stream} = $res->[1];
      return $res->[0];
    }

    # the filter returned a stream - if it contains something return the
    # first entry and stash it as the new alternate stream

    if (my ($new_evt) = $res->next) {
      $self->{_alt_stream} = $res;
      return $new_evt;
    }

    # we got a new alternate stream but it turned out to be empty
    # - this will happens for e.g. with an in place close (<foo />) that's
    # being removed. In that case, we fall off to loop back round and try
    # the next event from our main stream
  }

  # main stream exhausted so throw it away so we hit the short circuit
  # at the top and return nothing to indicate to our caller we're done

  delete $self->{_stream};
  return;
}

1;
