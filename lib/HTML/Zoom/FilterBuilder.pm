package HTML::Zoom::FilterBuilder;

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

sub _stream_from_proto {
  my ($self, $proto) = @_;
  my $ref = ref $proto;
  if (not $ref) {
    return $self->_stream_from_array({ type => 'TEXT', raw => $proto });
  } elsif ($ref eq 'ARRAY') {
    return $self->_stream_from_array(@$proto);
  } elsif ($ref eq 'CODE') {
    return $proto->();
  } elsif ($ref eq 'SCALAR') {
    require HTML::Zoom::Parser::BuiltIn;
    return HTML::Zoom::Parser::BuiltIn->html_to_stream($$proto);
  }
  die "Don't know how to turn $proto (ref $ref) into a stream";
}

sub _stream_concat {
  shift->_stream_from_array(@_)->flatten;
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
  my ($into, $passthrough, $content, $filter) =
    @{$options}{qw(into passthrough content filter)};
  sub {
    my ($evt, $stream) = @_;
    # We wipe the contents of @$into here so that other actions depending
    # on this (such as a repeater) can be invoked multiple times easily.
    # I -suspect- it's better for that state reset to be managed here; if it
    # ever becomes painful the decision should be revisited
    if ($into) {
      @$into = $content ? () : ($evt);
    }
    if ($evt->{is_in_place_close}) {
      return $evt if $passthrough || $content;
      return;
    }
    my $name = $evt->{name};
    my $depth = 1;
    my $_next = $content ? 'peek' : 'next';
    $stream = $filter->($stream) if $filter;
    my $collector = $self->_stream_from_code(sub {
      return unless $stream;
      while (my ($evt) = $stream->$_next) {
        $depth++ if ($evt->{type} eq 'OPEN');
        $depth-- if ($evt->{type} eq 'CLOSE');
        unless ($depth) {
          undef $stream;
          return if $content;
          push(@$into, $evt) if $into;
          return $evt if $passthrough;
          return;
        }
        push(@$into, $evt) if $into;
        $stream->next if $content;
        return $evt if $passthrough;
      }
      die "Never saw closing </${name}> before end of source";
    });
    return ($passthrough||$content) ? [ $evt, $collector ] : $collector;
  };
}

sub collect_content {
  my ($self, $options) = @_;
  $self->collect({ %{$options||{}}, content => 1 })
}

sub add_before {
  my ($self, $events) = @_;
  sub { return $self->_stream_from_array(@$events, $_[0]) };
}

sub add_after {
  my ($self, $events) = @_;
  my $coll_proto = $self->collect({ passthrough => 1 });
  sub {
    my ($evt) = @_;
    my $emit = $self->_stream_from_array(@$events);
    my $coll = &$coll_proto;
    return ref($coll) eq 'HASH' # single event, no collect
      ? [ $coll, $emit ]
      : [ $coll->[0], $self->_stream_concat($coll->[1], $emit) ];
  };
}

sub prepend_content {
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

sub append_content {
  my ($self, $events) = @_;
  my $coll_proto = $self->collect({ passthrough => 1, content => 1 });
  sub {
    my ($evt) = @_;
    if ($evt->{is_in_place_close}) {
      $evt = { %$evt }; delete @{$evt}{qw(raw is_in_place_close)};
      return [ $evt, $self->_stream_from_array(
        @$events, { type => 'CLOSE', name => $evt->{name} }
      ) ];
    }
    my $coll = &$coll_proto;
    my $emit = $self->_stream_from_array(@$events);
    return [ $coll->[0], $self->_stream_concat($coll->[1], $emit) ];
  };
}

sub replace {
  my ($self, $replace_with, $options) = @_;
  my $coll_proto = $self->collect($options);
  sub {
    my ($evt, $stream) = @_;
    my $emit = $self->_stream_from_proto($replace_with);
    my $coll = &$coll_proto;
    # For a straightforward replace operation we can, in fact, do the emit
    # -before- the collect, and my first cut did so. However in order to
    # use the captured content in generating the new content, we need
    # the collect stage to happen first - and it seems highly unlikely
    # that in normal operation the collect phase will take long enough
    # for the difference to be noticeable
    return
      ($coll
        ? (ref $coll eq 'ARRAY'
            ? [ $coll->[0], $self->_stream_concat($coll->[1], $emit) ]
            : $self->_stream_concat($coll, $emit)
          )
        : $emit
      );
  };
}

sub replace_content {
  my ($self, $replace_with, $options) = @_;
  $self->replace($replace_with, { %{$options||{}}, content => 1 })
}

sub repeat {
  my ($self, $repeat_for, $options) = @_;
  $options->{into} = \my @into;
  my $map_repeat = sub {
    local $_ = $self->_stream_from_array(@into);
    $_[0]->($_)
  };
  my $repeater = sub {
    $self->_stream_from_proto($repeat_for)
         ->map($map_repeat)
         ->flatten
  };
  $self->replace($repeater, $options);
}

sub repeat_content {
  my ($self, $repeat_for, $options) = @_;
  $self->repeat($repeat_for, { %{$options||{}}, content => 1 })
}

1;
