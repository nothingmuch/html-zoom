use HTML::Zoom;
use Test::More tests => 1;

my $zoom = HTML::Zoom->from_html('<p>Hello my name is <span id="name" /></p>');
my $html = $zoom->select('#name')->replace_content('Foo foo')->to_html;
is($html, '<p>Hello my name is <span id="#name">Foo foo</span>');
