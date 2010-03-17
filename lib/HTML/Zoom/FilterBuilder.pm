package HTML::Zoom::FilterBuilder;

use strict;
use warnings FATAL => 'all';
use base qw(HTML::Zoom::SubObject);
use HTML::Zoom::CodeStream;

sub _stream_from_code {
  shift->_zconfig->stream_utils->stream_from_code(@_)
}

sub _stream_from_array {
  shift->_zconfig->stream_utils->stream_from_array(@_)
}

sub _stream_from_proto {
  shift->_zconfig->stream_utils->stream_from_proto(@_)
}

sub _stream_concat {
  shift->_zconfig->stream_utils->stream_concat(@_)
}

sub _flatten_stream_of_streams {
  shift->_zconfig->stream_utils->flatten_stream_of_streams(@_)
}

sub set_attribute {
  my $self = shift;
  my ($name, $value) = $self->_parse_attribute_args(@_);
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

sub _parse_attribute_args {
  my $self = shift;
  # allow ->add_attribute(name => 'value')
  #    or ->add_attribute({ name => 'name', value => 'value' })
  my ($name, $value) = @_ > 1 ? @_ : @{$_[0]}{qw(name value)};
  return ($name, $self->_zconfig->parser->html_escape($value));
}

sub add_attribute {
  my $self = shift;
  my ($name, $value) = $self->_parse_attribute_args(@_);
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
  my $name = (ref($args) eq 'HASH') ? $args->{name} : $args;
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
  my ($into, $passthrough, $content, $filter, $flush_before) =
    @{$options}{qw(into passthrough content filter flush_before)};
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
    $stream = do { local $_ = $stream; $filter->($stream) } if $filter;
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
    if ($flush_before) {
      if ($passthrough||$content) {
        $evt = { %$evt, flush => 1 };
      } else {
        $evt = { type => 'EMPTY', flush => 1 };
      }
    }
    return ($passthrough||$content||$flush_before)
             ? [ $evt, $collector ]
             : $collector;
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
  my @between;
  my $repeat_between = delete $options->{repeat_between};
  if ($repeat_between) {
    $options->{filter} = sub {
      $_->select($repeat_between)->collect({ into => \@between })
    };
  }
  my $repeater = sub {
    my $s = $self->_stream_from_proto($repeat_for);
    # We have to test $repeat_between not @between here because
    # at the point we're constructing our return stream @between
    # hasn't been populated yet - but we can test @between in the
    # map routine because it has been by then and that saves us doing
    # the extra stream construction if we don't need it.
    $self->_flatten_stream_of_streams(do {
      if ($repeat_between) {
        $s->map(sub {
              local $_ = $self->_stream_from_array(@into);
              (@between && $s->peek)
                ? $self->_stream_concat(
                    $_[0]->($_), $self->_stream_from_array(@between)
                  )
                : $_[0]->($_)
            })
      } else {
        $s->map(sub {
              local $_ = $self->_stream_from_array(@into);
              $_[0]->($_)
          })
      }
    })
  };
  $self->replace($repeater, $options);
}

sub repeat_content {
  my ($self, $repeat_for, $options) = @_;
  $self->repeat($repeat_for, { %{$options||{}}, content => 1 })
}

1;
