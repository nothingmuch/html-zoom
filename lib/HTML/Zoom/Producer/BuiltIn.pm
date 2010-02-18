package HTML::Zoom::Producer::BuiltIn;

use strict;
use warnings FATAL => 'all';

sub new { bless({}, $_[0]) }

sub with_zconfig { shift }

sub html_from_stream {
  my ($class, $stream) = @_;
  my $html;
  while (my ($evt) = $stream->next) { $html .= $class->_event_to_html($evt) }
  return $html;
}

sub html_from_events {
  my ($class, $events) = @_;
  join '', map $class->_event_to_html($_), @$events;
}

sub _event_to_html {
  my ($self, $evt) = @_;
  # big expression
  if (defined $evt->{raw}) {
    $evt->{raw}
  } elsif ($evt->{type} eq 'OPEN') {
    '<'
    .$evt->{name}
    .(defined $evt->{raw_attrs}
        ? $evt->{raw_attrs}
        : do {
            my @names = @{$evt->{attr_names}};
            @names
              ? join(' ', '', map qq{${_}="${\$evt->{attrs}{$_}}"}, @names)
              : ''
          }
     )
    .($evt->{is_in_place_close} ? ' /' : '')
    .'>'
  } elsif ($evt->{type} eq 'CLOSE') {
    '</'.$evt->{name}.'>'
  } elsif ($evt->{type} eq 'EMPTY') {
    ''
  } else {
    die "No raw value in event and no special handling for type ".$evt->{type};
  }
}

1;
