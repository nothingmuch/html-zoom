use HTML::Zoom;
use Test::More;

my $zoom = HTML::Zoom->from_html(<<HTML);
<form class="myform" action="/somewhere">
<label />
<input />
</form>
HTML

my @fields = (
    { id => "foo", label => "foo", name => "foo", type => "text", value => 0 },
    { id => "bar", label => "bar", name => "bar", type => "radio", value => 1 },
);

my $h = $zoom->select('.myform')->repeat_content([
    map { my $field = $_; sub {
              $_->select('label')
               ->add_attribute( for => $field->{id} )
               ->then
               ->replace_content( $field->{label} )
               ->select('input')
               ->add_attribute( name => $field->{name} )
               ->then
               ->add_attribute( type => $field->{type} )
               ->then
               ->add_attribute( value => $field->{value} )
           } } @fields
       ])->to_html;

ok 1;
done_testing;
