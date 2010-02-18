package HTML::Zoom::MatchWithoutFilter;

use strict;
use warnings FATAL => 'all';

sub construct {
  bless({
    zoom => $_[1], match => $_[2], fb => $_[3],
  }, $_[0]);
}

sub DESTROY {}

sub AUTOLOAD {
  my $meth = our $AUTOLOAD;
  $meth =~ s/.*:://;
  my $self = shift;
  if (my $cr = $self->{fb}->can($meth)) {
    return $self->{zoom}->with_filter(
      $self->{match}, $self->{fb}->$cr(@_)
    );
  }
  die "Filter builder ${\$self->{fb}} does not provide action ${meth}";
}

1;
