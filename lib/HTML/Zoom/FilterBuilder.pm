package HTML::Zoom::FilterBuilder;

use Devel::Dwarn;

use strict;
use warnings FATAL => 'all';
use HTML::Zoom::CodeStream;

sub new { bless({}, shift) }

sub _stream_from_code {
  HTML::Zoom::CodeStream->new({ code => $_[1] })
}

sub _stream_from_array {
  shift; # lose $self
  HTML::Zoom::CodeStream->from_array(@_)
}

sub _stream_concat {
  shift; # lose $self
  my @streams = @_;
  my $cur_stream = shift(@streams) or die "No streams passed";
  HTML::Zoom::CodeStream->new({
    code => sub {
      return unless $cur_stream;
      my $evt;
      until (($evt) = $cur_stream->next) {
        return unless $cur_stream = shift(@streams);
      }
      return $evt;
    }
  });
}

sub set_attribute {
  my ($self, $args) = @_;
  my ($name, $value) = @{$args}{qw(name value)};
  sub {
    my $a = (my $evt = $_[0])->{attrs};
    my $e = exists $a->{$name};
    +{ %$evt, raw => undef, raw_attrs => undef,
       attrs => { %$a, $name => $value },
      ($e # add to name list if not present
        ? ()
        : (attr_names => [ @{$evt->{attr_names}}, $name ]))
     }
   };
}

sub add_attribute {
  my ($self, $args) = @_;
  my ($name, $value) = @{$args}{qw(name value)};
  sub {
    my $a = (my $evt = $_[0])->{attrs};
    my $e = exists $a->{$name};
    +{ %$evt, raw => undef, raw_attrs => undef,
       attrs => {
         %$a,
         $name => join(' ', ($e ? $a->{$name} : ()), $value)
      },
      ($e # add to name list if not present
        ? ()
        : (attr_names => [ @{$evt->{attr_names}}, $name ]))
    }
  };
}

sub remove_attribute {
  my ($self, $args) = @_;
  my $name = $args->{name};
  sub {
    my $a = (my $evt = $_[0])->{attrs};
    return $evt unless exists $a->{$name};
    $a = { %$a }; delete $a->{$name};
    +{ %$evt, raw => undef, raw_attrs => undef,
       attrs => $a,
       attr_names => [ grep $_ ne $name, @{$evt->{attr_names}} ]
    }
  };
}

sub collect {
  my ($self, $options) = @_;
  my ($into, $passthrough, $inside) = @{$options}{qw(into passthrough inside)};
  sub {
    my ($evt, $stream) = @_;
    push(@$into, $evt) if $into && !$inside;
    if ($evt->{is_in_place_close}) {
      return $evt if $passthrough || $inside;
      return;
    }
    my $name = $evt->{name};
    my $depth = 1;
    my $_next = $inside ? 'peek' : 'next';
    my $collector = $self->_stream_from_code(sub {
      return unless $stream;
      while (my ($evt) = $stream->$_next) {
        $depth++ if ($evt->{type} eq 'OPEN');
        $depth-- if ($evt->{type} eq 'CLOSE');
        unless ($depth) {
          undef $stream;
          return if $inside;
          push(@$into, $evt) if $into;
          return $evt if $passthrough;
          return;
        }
        push(@$into, $evt) if $into;
        $stream->next if $inside;
        return $evt if $passthrough;
      }
      die "Never saw closing </${name}> before end of source";
    });
    return ($passthrough||$inside) ? [ $evt, $collector ] : $collector;
  };
}

sub add_before {
  my ($self, $events) = @_;
  sub { return $self->_stream_from_array(@$events, $_[0]) };
}

sub add_after {
  my ($self, $events) = @_;
  sub {
    my ($evt) = @_;
    my $emit = $self->_stream_from_array(@$events);
    my $coll = $self->collect({ passthrough => 1 })->(@_);
    return ref($coll) eq 'HASH' # single event, no collect
      ? [ $coll, $emit ]
      : [ $coll->[0], $self->_stream_concat($coll->[1], $emit) ];
  };
}

sub prepend_inside {
  my ($self, $events) = @_;
  sub {
    my ($evt) = @_;
    if ($evt->{is_in_place_close}) {
      $evt = { %$evt }; delete @{$evt}{qw(raw is_in_place_close)};
      return [ $evt, $self->_stream_from_array(
        @$events, { type => 'CLOSE', name => $evt->{name} }
      ) ];
    }
    return $self->_stream_from_array($evt, @$events);
  };
}

sub append_inside {
  my ($self, $events) = @_;
  sub {
    my ($evt) = @_;
    if ($evt->{is_in_place_close}) {
      $evt = { %$evt }; delete @{$evt}{qw(raw is_in_place_close)};
      return [ $evt, $self->_stream_from_array(
        @$events, { type => 'CLOSE', name => $evt->{name} }
      ) ];
    }
    my $coll = $self->collect({ passthrough => 1, inside => 1 })->(@_);
    my $emit = $self->_stream_from_array(@$events);
    return [ $coll->[0], $self->_stream_concat($coll->[1], $emit) ];
  };
}

sub replace {
  my ($self, $events, $options) = @_;
  sub {
    my ($evt, $stream) = @_;
    my $emit = $self->_stream_from_array(@$events);
    my $coll = $self->collect($options)->(@_);
    return
      ($coll
        ? (ref $coll eq 'ARRAY'
            ? [ $coll->[0], $self->_stream_concat($emit, $coll->[1]) ]
            : $self->_stream_concat($emit, $coll)
          )
        : $emit
      );
  };
}

1;
