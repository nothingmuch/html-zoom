use strict;
use warnings FATAL => 'all';
use Test::More;

use HTML::Zoom::Parser::BuiltIn;
use HTML::Zoom::Producer::BuiltIn;
use HTML::Zoom::SelectorParser;
use HTML::Zoom::FilterBuilder;
use HTML::Zoom::FilterStream;

my $tmpl = <<END;
<body>
  <div class="main">
    <span class="hilight name">Bob</span>
    <span class="career">Builder</span>
    <hr />
  </div>
</body>
END

sub src_stream { HTML::Zoom::Parser::BuiltIn->html_to_stream($tmpl); }

sub html_sink { HTML::Zoom::Producer::BuiltIn->html_from_stream($_[0]) }

my $fb = HTML::Zoom::FilterBuilder->new;

my $sp = HTML::Zoom::SelectorParser->new;

sub filter {
  my ($stream, $sel, $cb) = @_;
  return HTML::Zoom::FilterStream->new({
    stream => $stream,
    match => $sp->parse_selector($sel),
    filter => do { local $_ = $fb; $cb->($fb) }
  });
}

sub run_for (&;$) {
  my $cb = shift;
  (html_sink
    (filter
      src_stream,
      (shift or '.main'),
      $cb
    )
  )
}

my ($expect, @ev);

($expect = $tmpl) =~ s/class="main"/class="foo"/;

is(
  run_for { $_->set_attribute({ name => 'class', value => 'foo' }) },
  $expect,
  'set attribute on existing attribute'
);

($expect = $tmpl) =~ s/class="main"/class="main" foo="bar"/;

is(
  run_for { $_->set_attribute({ name => 'foo', value => 'bar' }) },
  $expect,
  'set attribute on non existing attribute'
);

($expect = $tmpl) =~ s/class="main"/class="main foo"/;

is(
  run_for { $_->add_attribute({ name => 'class', value => 'foo' }) },
  $expect,
  'add attribute on existing attribute'
);

($expect = $tmpl) =~ s/class="main"/class="main" foo="bar"/;

is(
  run_for { $_->add_attribute({ name => 'foo', value => 'bar' }) },
  $expect,
  'add attribute on non existing attribute'
);

($expect = $tmpl) =~ s/ class="main"//;

is(
  run_for { $_->remove_attribute({ name => 'class' }) },
  $expect,
  'remove attribute on existing attribute'
);

is(
  run_for { $_->remove_attribute({ name => 'foo' }) },
  $tmpl,
  'remove attribute on non existing attribute'
);

($expect = $tmpl) =~ s/(?=<div)/O HAI/;

my $ohai = [ { type => 'TEXT', raw => 'O HAI' } ];

is(
  run_for { $_->add_before($ohai) },
  $expect,
  'add_before ok'
);

($expect = $tmpl) =~ s/(?<=<\/div>)/O HAI/;

is(
  run_for { $_->add_after($ohai) },
  $expect,
  'add_after ok'
);

($expect = $tmpl) =~ s/(?<=class="main">)/O HAI/;

is(
  run_for { $_->prepend_inside($ohai) },
  $expect,
  'prepend_inside ok'
);

($expect = $tmpl) =~ s/<hr \/>/<hr>O HAI<\/hr>/;

is(
  (run_for { $_->prepend_inside($ohai) } 'hr'),
  $expect,
  'prepend_inside ok with in place close'
);

is(
  run_for { $_->replace($ohai) },
'<body>
  O HAI
</body>
',
  'replace ok'
);

@ev = ();

is(
  run_for { $_->collect({ into => \@ev }) },
  '<body>
  
</body>
',
  'collect removes without passthrough'
);

is(
  HTML::Zoom::Producer::BuiltIn->html_from_events(\@ev),
  '<div class="main">
    <span class="hilight name">Bob</span>
    <span class="career">Builder</span>
    <hr />
  </div>',
  'collect collected right events'
);

@ev = ();

is(
  run_for { $_->collect({ into => \@ev, inside => 1 }) },
  '<body>
  <div class="main"></div>
</body>
',
  'collect w/inside removes correctly'
);

is(
  HTML::Zoom::Producer::BuiltIn->html_from_events(\@ev),
  '
    <span class="hilight name">Bob</span>
    <span class="career">Builder</span>
    <hr />
  ',
  'collect w/inside collects correctly'
);

done_testing;
