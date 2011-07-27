use strict;
use Test::More;
use Test::Exception;
use Beacon;

my $b = Beacon->new->parse("t/beacon1.txt");
isa_ok $b, 'Beacon';

is_deeply( { $b->meta }, {
  'FORMAT' => 'BEACON',
  'TARGET' => 'http://example.com/{ID}',
  'FOO' => 'bar doz',
  'PREFIX' => 'x:'
}, "parsing meta fields" );

is( $b->count, 8, 'parsed 8 links' );
is( $b->count_ids, 8, 'for 8 ids' );

my %tests = (
    0 => ['1','',''],
    1 => ['099','',''],
    2 => ['0','',''],
    foo => ['','',''],
    bar => ['','doz',''],
    b   => ['7a','',''],
    c   => [7,'',''],
    d   => ['x','','y:z'],
);
while (my ($id,$expect) = each(%tests)) {
    my $l = $b->get($id);
    is_deeply $l, $expect, "raw link for id $id as expected";
    my @e = $b->expand( $id, @$l );
    $l->[2] = "http://example.com/$id" if $l->[2] eq '';
    my $idexp = "x:$id";
    is_deeply \@e, [$idexp, @$l], "expanded link for $id as expected";
    $l = $b->get_expanded($id);
    is_deeply \@e, $l;
}

dies_ok { $b->parse("~") } 'parse non-existing file';
#is( $b->errors, 1 );

#my $e = $b->lasterror;
#is( $e, 'Failed to open ~', 'lasterror, scalar context' );

#my @es = $b->lasterror;
#is_deeply( \@es, [ 'Failed to open ~', 0, '' ], 'lasterror, list context' );

#$b->parse( { } );
#is( $b->errors, 1, 'cannot parse a hashref' );

# string parsing
$b->parse( \"x:from|x:to\n\n|comment" );
is( $b->count, 1, 'parse from string' );

use Data::Dumper;
my $l = $b->get('x:from');
is_deeply( $l, ['x:to','',''], 'one link' );

done_testing;
__END__

is_deeply( [$b->link], ['x:from','','','x:to'] );
is_deeply( [$b->expanded], ['x:from','','','x:to'] );

$b->parse( \"\xEF\xBB\xBFx:from|x:to", links => sub { @l = @_; } );
is( $b->line, 1 );
is( $b->errors, 0 );
is_deeply( \@l, [ 'x:from', '', '', 'x:to' ], 'BOM' );


my @tmplines = ( '#FOO: bar', '#DOZ', '#BAZ: doz' );
$b->parse( from => sub { return shift @tmplines; } );
is( $b->line, 3, 'parse from code ref' );
is( $b->count, 0, '' );
is( $b->metafields, "#FORMAT: BEACON\n#BAZ: doz\n#FOO: bar\n#COUNT: 0\n" );
is( $b->link, undef, 'no links' );

$b->parse( from => sub { die 'hard'; } );
is( $b->errors, 1 );
ok( $b->lasterror =~ /^hard/, 'dead input will not kill us' );



