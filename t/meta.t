use strict;
use Test::More;
use Test::Exception;
use Beacon;

my $b = Beacon->new;

my %m = $b->meta;
is_deeply \%m, { 'FORMAT' => 'BEACON' }, 'meta fields';

is_deeply $b->meta('fOrMaT'), 'BEACON', 'FORMAT';
is_deeply $b->meta('foo'), undef, 'unknown';
is_deeply $b->meta( {} ), undef, 'no scalar';

$b->meta( 'prefix' => 'http://foo.org/' );
is_deeply { $b->meta }, { 'FORMAT' => 'BEACON', 'PREFIX' => 'http://foo.org/' }, 'meta fields';
$b->meta( 'prefix' => 'u:' ); # URI prefix
$b->meta( 'prefix' => '' );
is $b->meta('prefix'), undef, 'unset PREFIX';

foreach my $name (' ', '~') {
  throws_ok { $b->meta($name,'x') } qr{^Invalid field name: $name}, 'invalid field name';
}

$b->meta('COUNT' => '003');
is $b->meta('count'), 3, 'COUNT';
throws_ok { $b->meta('COUNT','x') } qr{^Invalid COUNT field: x}, 'invalid COUNT';

$b->meta(' Feed','http://example.org/?get=f%65ed');
is $b->meta('feed'), 'http://example.org/?get=feed', 'FEED';
foreach my $feed (qw(some:uri http:// x)) {
  throws_ok { $b->meta('FEED',$feed) } qr{^Invalid FEED field: $feed}, 'invalid FEED';
}

# +FORMAT


$b->meta( 'PREFIX' => 'http://example.org/?foo=%65&bar=' );
is $b->meta('prefix'), 'http://example.org/?foo=e&bar=', 'PREFIX';
$b->meta( 'PREFIX' => 'u:' );
is $b->meta('PREFIX'), 'u:', 'PREFIX';
throws_ok { $b->meta('PREFIX','x') } qr{^Invalid PREFIX}, 'invalid PREFIX';

throws_ok { $b->meta('TIMESTAMP','abc') } qr{^Invalid TIMESTAMP}, 'invalid TIMESTAMP';
for my $time (qw(1311653426 2011-07-26T04:10:26Z)) {
    $b->meta('TIMESTAMP',$time);
    is $b->meta('TIMESTAMP'), '2011-07-26T04:10:26Z', 'TIMESTAMP';
}

$b->meta('version','0.2');
throws_ok { $b->meta('VERSION','-') } qr{^Invalid VERSION}, 'invalid VERSION';
is $b->meta('VERSION'), 0.2, 'VERSION';

done_testing;

__END__
eval { $b->meta( 'revisit' => 'Sun 3rd Nov, 1943' ); }; 
ok( $@ , 'detect invalid REVISIT');
$b->meta( 'REvisit' => '2010-02-31T12:00:01' );
is_deeply( { $b->meta() }, 
  { 'FORMAT' => 'BEACON', 
    'REVISIT' => '2010-03-03T12:00:01' } );
$b->meta( 'REVISIT' => '' );

is( $b->meta( 'EXAMPLES' ), undef );
$b->meta( 'EXAMPLES', 'foo | bar||doz ' );
is( $b->meta('EXAMPLES'), 'foo|bar|doz', 'EXAMPLES' );
$b->meta( 'EXAMPLES', '|' );
is( $b->meta('EXAMPLES'), undef );
$b->meta( 'EXAMPLES', '' );

my $expected = { 'FORMAT' => 'BEACON', 'FOO' => 'bar', 'X' => 'YZ' };
$b->meta('foo' => 'bar ', ' X ' => " Y\nZ");
is_deeply( { $b->meta() }, $expected );
$b->meta('foo',''); # unset
is_deeply( { $b->meta() }, { 'FORMAT' => 'BEACON', 'X' => 'YZ' } );

eval { $b->meta( 'format' => 'foo' ); }; ok( $@, 'detect invalid FORMAT' );
$b->meta( 'format' => 'FOO-BEACON' );
is( $b->meta('format'), 'FOO-BEACON' );
