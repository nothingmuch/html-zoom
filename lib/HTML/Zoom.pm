package HTML::Zoom;

use strict;
use warnings FATAL => 'all';

use HTML::Zoom::ZConfig;
use HTML::Zoom::MatchWithoutFilter;

sub new {
  my ($class, $args) = @_;
  my $new = {};
  $new->{zconfig} = HTML::Zoom::ZConfig->new($args->{zconfig}||{});
  bless($new, $class);
}

sub zconfig { shift->_self_or_new->{zconfig} }

sub _self_or_new {
  ref($_[0]) ? $_[0] : $_[0]->new
}

sub _with {
  bless({ %{$_[0]}, %{$_[1]} }, ref($_[0]));
}

sub from_html {
  my $self = shift->_self_or_new;
  $self->_with({
    initial_events => $self->zconfig->parser->html_to_events($_[0])
  });
}

sub to_stream {
  my $self = shift;
  die "No events to build from - forgot to call from_html?"
    unless $self->{initial_events};
  my $sutils = $self->zconfig->stream_utils;
  my $stream = $sutils->stream_from_array(@{$self->{initial_events}});
  foreach my $filter_spec (@{$self->{filters}||[]}) {
    $stream = $sutils->wrap_with_filter($stream, @{$filter_spec});
  }
  $stream
}

sub to_html {
  my $self = shift;
  $self->zconfig->producer->html_from_stream($self->to_stream);
}

sub memoize {
  my $self = shift;
  ref($self)->new($self)->from_html($self->to_html);
}

sub with_filter {
  my ($self, $selector, $filter) = @_;
  my $match = $self->parse_selector($selector);
  $self->_with({
    filters => [ @{$self->{filters}||[]}, [ $match, $filter ] ]
  });
}

sub select {
  my ($self, $selector) = @_;
  my $match = $self->parse_selector($selector);
  return HTML::Zoom::MatchWithoutFilter->construct(
    $self, $match, $self->zconfig->filter_builder,
  );
}

# There's a bug waiting to happen here: if you do something like
#
# $zoom->select('.foo')
#      ->remove_attribute({ class => 'foo' })
#      ->then
#      ->well_anything_really
#
# the second action won't execute because it doesn't match anymore.
# Ideally instead we'd merge the match subs but that's more complex to
# implement so I'm deferring it for the moment.

sub then {
  my $self = shift;
  die "Can't call ->then without a previous filter"
    unless $self->{filters};
  $self->select($self->{filters}->[-1][0]);
}

sub parse_selector {
  my ($self, $selector) = @_;
  return $selector if ref($selector); # already a match sub
  $self->zconfig->selector_parser->parse_selector($selector);
}

1;

=head1 NAME

HTML::Zoom - selector based streaming template engine

=head1 SYNOPSIS

  use HTML::Zoom;

  my $template = <<HTML;
  <html>
    <head>
      <title>Hello people</title>
    </head>
    <body>
      <h1 id="greeting">Placeholder</h1>
      <div id="list">
        <span>
          <p>Name: <span class="name">Bob</span></p>
          <p>Age: <span class="age">23</span></p>
        </span>
        <hr class="between" />
      </div>
    </body>
  </html>
  HTML

  my $output = HTML::Zoom
    ->from_html($template)
    ->select('title, #greeting')->replace_content('Hello world & dog!')
    ->select('#list')->repeat_content(
        [
          sub {
            $_->select('.name')->replace_content('Matt')
              ->select('.age')->replace_content('26')
          },
          sub {
            $_->select('.name')->replace_content('Mark')
              ->select('.age')->replace_content('0x29')
          },
          sub {
            $_->select('.name')->replace_content('Epitaph')
              ->select('.age')->replace_content('<redacted>')
          },
        ],
        { repeat_between => '.between' }
      )
    ->to_html;

will produce:

=begin testinfo

  my $expect = <<HTML;

=end testinfo

  <html>
    <head>
      <title>Hello world &amp; dog!</title>
    </head>
    <body>
      <h1 id="greeting">Hello world &amp; dog!</h1>
      <div id="list">
        <span>
          <p>Name: <span class="name">Matt</span></p>
          <p>Age: <span class="age">26</span></p>
        </span>
        <hr class="between" />
        <span>
          <p>Name: <span class="name">Mark</span></p>
          <p>Age: <span class="age">0x29</span></p>
        </span>
        <hr class="between" />
        <span>
          <p>Name: <span class="name">Epitaph</span></p>
          <p>Age: <span class="age">&lt;redacted&gt;</span></p>
        </span>
        
      </div>
    </body>
  </html>

=begin testinfo

  HTML
  is($output, $expect, 'Synopsis code works ok');

=end testinfo

=head1 SOMETHING ELSE

=cut
