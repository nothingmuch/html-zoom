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
    my $a = (my $evt = shift)->{attrs};
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
    my $a = (my $evt = shift)->{attrs};
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
    my $a = (my $evt = shift)->{attrs};
    return $evt unless exists $a->{$name};
    $a = { %$a }; delete $a->{$name};
    +{ %$evt, raw => undef, raw_attrs => undef,
       attrs => $a,
       attr_names => [ grep $_ ne $name, @{$evt->{attr_names}} ]
    }
  };
}

sub add_before {
  my ($self, $events) = @_;
  sub { return $self->_stream_from_array(@$events, shift) };
}

sub add_after {
  my ($self, $events) = @_;
  sub {
    my ($evt, $stream) = @_;
    my $emit = $self->_stream_from_array(@$events);
    if ($evt->{is_in_place_close}) {
      return [ $evt, $emit ];
    }
    my ($filtered_evt, $coll) = @{$self->collect(undef, 1)->(@_)};
    return [ $filtered_evt, $self->_stream_concat($coll, $emit) ];
  };
}  

sub prepend_inside {
  my ($self, $events) = @_;
  sub {
    my $evt = shift;
    if ($evt->{is_in_place_close}) {
      $evt = { %$evt }; delete @{$evt}{qw(raw is_in_place_close)};
      return [ $evt, $self->_stream_from_array(
        @$events, { type => 'CLOSE', name => $evt->{name} }
      ) ];
    }
    return $self->_stream_from_array($evt, @$events);
  };
}

sub replace {
  my ($self, $events) = @_;
  sub {
    my ($evt, $stream) = @_;
    my $emit = $self->_stream_from_array(@$events);
    if ($evt->{is_in_place_close}) {
      return $emit
    }
    return $self->_stream_concat($emit, $self->collect->(@_));
  };
}

sub collect {
  my ($self, $into, $passthrough) = @_;
  sub {
    my ($evt, $stream) = @_;
    push(@$into, $evt) if $into;
    if ($evt->{is_in_place_close}) {
      return $evt if $passthrough;
      return;
    }
    my $name = $evt->{name};
    my $depth = 1;
    my $collector = $self->_stream_from_code(sub {
      return unless $stream;
      while (my ($evt) = $stream->next) {
        $depth++ if ($evt->{type} eq 'OPEN');
        $depth-- if ($evt->{type} eq 'CLOSE');
        unless ($depth) {
          undef $stream;
          return $evt if $passthrough;
          return;
        }
        push(@$into, $evt) if $into;
        return $evt if $passthrough;
      }
      die "Never saw closing </${name}> before end of source";
    });
    return $passthrough ? [ $evt, $collector ] : $collector;
  };
}

1;
