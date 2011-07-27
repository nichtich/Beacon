use strict;
use Test::More;
use Test::Exception;
use Beacon;

my $b = Beacon->new( PREFIX => 'http://foo.org/' );
isa_ok $b,'Beacon';
is $b->meta('PREFIX'), 'http://foo.org/', 'new with prefix';
is $b->count, 0, 'empty by default';

my $c = Beacon->new->meta( PREFIX => 'http://foo.org' );
is_deeply( $b, $c, 'set with meta' );

is_deeply [ $b->expand( 0 ) ],       [ 'http://foo.org/0', '', '', '' ], 'expand';
is_deeply [ $b->expand( 0, 0 ) ],    [ 'http://foo.org/0', '0', '', '' ], 'expand';
is_deeply [ $b->expand( 1, 2, 3 ) ], [ 'http://foo.org/1', '2', '3', '' ], 'expand';
is_deeply [ $b->expand( '' ) ],      [ 'http://foo.org/', '', '', '' ], 'expand';
is_deeply [ $b->expand( undef ) ],   [ 'http://foo.org/', '', '', '' ], 'expand';
is_deeply [ Beacon->new->expand( 'x' ) ], [ '', '', '', '' ], 'expand';
is_deeply [ Beacon->new->expand( undef ) ], [ '', '', '', '' ], 'expand';
is_deeply [ Beacon->new->expand( 'id:0' ) ], [ 'id:0', '', '', '' ], 'expand';

$b->meta('prefix' => undef);
is $b->meta('prefix') ,undef,'unset PREFIX';

$b = Beacon->new( TARGET => 'http://foo.org/{TARGET}' );
#my @l = $b->parselink("f:rom|||x");
#is_deeply( \@l, ['f:rom','','','x'], 'targetprefix' );
is_deeply( [ $b->expand('f:rom','','','x') ], ['f:rom','','','http://foo.org/x'], 'targetprefix' );

done_testing;

# is( $b->meta('COUNT'), undef, 'meta("COUNT")' );
# is( $b->count, 0, 'count()' );
# $b->meta('count' => 7);
# is( $b->count, 7, 'count()' );
# is( $b->line, 0, 'line()' );

__END__

# {ID} or {LABEL} in #TARGET optional
$b->meta( 'target' => 'u:ri:' );
is( $b->meta('target'), 'u:ri:{ID}' );

# TARGETPREFIX
$b = beacon( { TARGETPREFIX => 'http://foo.org/' } );
ok( !$b->lasterror );
my @l = $b->appendlink("f:rom","","","x");
is_deeply( \@l, ['f:rom','','','x'], 'targetprefix' );
is_deeply( [ $b->expanded ], ['f:rom','','','http://foo.org/x'], 'targetprefix' );

@l = $b->expand("f:rom","","","x");
is_deeply( \@l, ['f:rom','','','http://foo.org/x'], 'expand' );
is( $b->count, 1 );

eval { $b = beacon( { TARGET => 'u:ri', TARGETPREFIX => 'http://foo.org/' } ); };
ok( $@, 'TARGET and TARGETPREFIX cannot be set both' );

$b = beacon( $expected );
is_deeply( { $b->meta() }, $expected );
is( $b->errors, 0 );

my $haserror;

$b = beacon( errors => sub { $haserror = 1; } ); 
$b->meta('PREFIX','x:');
$b->meta('TARGETPREFIX','y:');
ok( $b->appendlink('0','','','0'), 'zero is valid source' );
ok( !$b->errors && !$haserror, 'error handler not called' );

$b = beacon( $expected, errors => sub { $haserror = 1; } ); 
ok( !$b->errors && !$haserror, 'error handler' );

$b->appendlink('0');
ok( $b->errors && $haserror, 'error handler' );

$b = beacon();
$b->meta( 'feed' => 'http://example.com', 'target' => 'http://example.com/{ID}' );
$b->meta( 'target' => 'http://example.com/{LABEL}' );
is( $b->meta('target'), 'http://example.com/{LABEL}' );

$b = beacon();
ok (! $b->appendline( undef ), 'undef line');

my %t;

=head1
# split BEACON format link without validating or expanding

# line parsing (invalid URI not checked)
%t = (
  "qid" => ["qid","","",""],
  "qid|\t" => ["qid","","",""],
  "qid|" => ["qid","","",""],
  "qid|lab" => ["qid","lab","",""],
  "qid|  lab |dsc" => ["qid","lab","dsc",""],
  "qid| | dsc" => ["qid","","dsc",""],
  " qid||dsc" => ["qid","","dsc",""],
  "qid |u:ri" => ["qid","","","u:ri"],
  "qid |lab  |dsc|u:ri" => ["qid","lab","dsc","u:ri"],
  "qid|lab|u:ri" => ["qid","lab","","u:ri"],
  " \t" => [],
  "" => [],
  "qid|lab|dsc|u:ri|foo" => ["qid","lab","dsc","u:ri"]
  "|qid|u:ri" => [],
  "qid|lab|dsc|abc" => "URI part has not valid URI form: abc",
);
while (my ($line, $link) = each(%t)) {
    # my @l = $b->appendline( $line );
use Data::Dumper;
print "L:$line\n";
print Dumper(\@l)."\n";
    #$r = parsebeaconlink( $line ); # without prefix or target
    #is_deeply( \@l, $link );
}
=cut

# with prefix and target
$b = beacon({PREFIX=>'x:',TARGET=>'y:'});
ok( $b->appendline( "0|z" ), 'appendline, scalar' );

%t = ("qid |u:ri" => ['qid','u:ri','','']);
while (my ($line, $link) = each(%t)) {
    ok( $b->appendline( $line ), 'appendline, scalar' );

    my @l = $b->appendline( $line );
    @l = @l[0..3];
    is_deeply( \@l, $link, 'appendline, list' );
    # TODO: test fullid and fulluri

    ok( $b->appendlink( @l ), 'appendlink, scalar' );

    my @l2 = $b->appendlink( @l );
    @l2 = @l2[0..3];
    is_deeply( \@l2, $link, 'appendlink, list' );
}

# with prefix only
$b = beacon({PREFIX=>'x:'});
%t = ( 
  'a|b|http://example.com/bar' => ['x:a','b','','http://example.com/bar'],
  "a|b|http://example.com/bar\n" => ['x:a','b','','http://example.com/bar']  
);
while (my ($line, $link) = each(%t)) {
    ok( $b->appendline($line) );
    $b->expanded; # multiple calls should not alter the link
    $line =~ s/\n//;
    is_deeply( [ $b->expanded ], $link, "expanded with PREFIX: $line" );
}

# file parsing
$b = beacon("~");
is( $b->errors, 1, 'failed to open file' );

$b = beacon( undef );
is( $b->errors, 0, 'no file specified' );

$b = beacon( \"#COUNT: 2\nf:rom|t:o" );
is( $b->count, 2 );
ok( !$b->parse() );
is( $b->lasterror, "expected 2 links, but got 1", "check expected link count" );

# expected examples
$b = beacon( \"#EXAMPLES: a:b|c:d\na:b|to:1\nc:d|to:2" );
ok( $b->parse() );

$b = beacon( \"#EXAMPLES: a:b|c\na:b|to:1" );
$b->parse();
is_deeply( [ $b->lasterror ], [ 'examples not found: c',2,''], 'examples' );

$b = beacon( \"#EXAMPLES: a\n#PREFIX x:\na|to:1" );
ok( $b->parse() );

$b = beacon( \"#EXAMPLES: x:a\n#PREFIX x:\na|to:1" );
ok( $b->parse() );

# ensure that IDs are URIs
$b = beacon( \"xxx |foo" );
$b->parse();
is_deeply( [ $b->lasterror ], [ 'source is no URI: xxx',1,'xxx |foo' ], 
            'skipped non-URI id' );

# pull parsing
$b = beacon( \"\nid:1|t:1\n|comment\n" );
is_deeply( [$b->nextlink], ["id:1","","","t:1"] );
is_deeply( [$b->expanded], ["id:1","","","t:1"] );
is_deeply( [$b->nextlink], [] );
is_deeply( [$b->link], ["id:1","","","t:1"], 'last link' );

$b = beacon( \"id:1|t:1\na b|\nid:2|t:2" );
is_deeply( [$b->nextlink], ["id:1","","","t:1"] );
# a b| is ignored
is_deeply( [$b->nextlink], ["id:2","","","t:2"] );
is_deeply( [$b->link], ["id:2","","","t:2"] );
ok( !$b->nextlink );
is( $b->errors, 1 );
is_deeply( [ $b->lasterror ], [ 'source is no URI: a b',2,'a b|' ] );

use Data::Validate::URI qw(is_uri);

# check method 'plainbeaconlink'
my @p = ( 
    ["",""],
    ["","","","http://example.com"]
);
while (@p) {
    my $in = shift @p;
    is( plainbeaconlink( @{$in} ), '', 'plainbeaconlink = ""');
}

@p = (
    ["a","b","c ",""], "a|b|c",
    ["a"," b","",""], "a|b",
    ["a","","",""], "a",
    ["a"," b ","c"," z"] => 'a|b|c|z',
    ["a","","","z"] => 'a|||z',
    ["a"," "," b "] => 'a||b',
);
while (@p) {
    my $in = shift @p;
    my $out = shift @p;
    my $line = plainbeaconlink( @{$in} );
    is( $line, $out, 'plainbeaconlink');

    $line = "#PREFIX: http://example.org/\n$line";
    $b = beacon( \$line );
    ok( !$b->parse ); # TARGET is not an URI

    $line = "#TARGET: foo:{ID}\n$line";
    $b = beacon( \$line );
    my $l = [$b->nextlink];
    @$in = map { s/^\s+|\s+$//g; $_; } @$in;
    push (@$in,'') while ( @$in < 4 );

    is_deeply( $in, $l, 'plainbeaconlink + PREFIX + TARGET' );

    my @exp = @$in;
    my $id = $in->[0];
    $exp[0] = "http://example.org/$id";
    $exp[3] = "foo:$id";
    is_deeply( [$b->expanded], \@exp, 'plainbeaconlink + PREFIX + TARGET' );
}

@p = ( # with 'to' field
#    ["a","b","","u:ri"] => 'a|b|u:ri',
#    ["a","","",""] => 'a|u:ri',
    ["a","b","","foo:x"], "a|b|foo:x",
    ["a","","","foo:x"], "a|foo:x",
    ["a","b","c","foo:x"], "a|b|c|foo:x",
    #["x","a||","","http://example.com|"], "x|a|http://example.com",
    #["x","","|d","foo:bar"], "x||d|foo:bar",
    #["x","|","","http://example.com"], "x|http://example.com",
);
while (@p) {
    my $in = shift @p;
    my $out = shift @p;
    my $line = plainbeaconlink( @{$in} );
    is( $line, $out, 'plainbeaconlink');

    @$in = map { s/\|//g; $_; } @$in;
    $line = "#PREFIX: http://example.org/\n$line";
    $b = beacon( \$line );

    my $l = [$b->nextlink];
    #pop @$l; # fullid
    #pop @$l; # fulluri
    
    is_deeply($l, $in);
}

# ignore additional params
is('x', plainbeaconlink('x','','','','foo','bar'));

# link expansion

$b = beacon( \"#TARGET: http://foo.org/{LABEL}\nf:rom|x" );
is_deeply( [$b->nextlink], ['f:rom','x','',''] );
is_deeply( [$b->expanded], ['f:rom','x','',,'http://foo.org/x'] );

$b = beacon( \"#TARGET: http://foo.org/{ID}\nx:y" );
is_deeply( [$b->nextlink], ['x:y','','',''] );
is_deeply( [$b->expanded], ['x:y','','',,'http://foo.org/x:y'] );


$b = beacon( \"#PREFIX: u:\n#TARGET: z:{ID}\n\$1" );
is_deeply( [$b->nextlink], ['$1','','','']);
is_deeply( [$b->expanded], ['u:$1','','','z:$1'] );

$b = beacon( \"a:b|c:d" );
is_deeply( [$b->nextlink], ['a:b','','','c:d']);
is_deeply( [$b->expanded], ['a:b','','','c:d'] );

$b = beacon( \"#TARGET: f:{ID}\na:b|c:d" );
is_deeply( [$b->nextlink], ['a:b','c:d','',''] );
is_deeply( [$b->expanded], ['a:b','c:d','','f:a:b'], 'TARGET changes parsing' );

$b = beacon( \"#TARGET: f:{LABEL}\na:b|c:d" );
is_deeply( [$b->nextlink], ['a:b','c:d','','']);
is_deeply( [$b->expanded],['a:b','c:d','','f:c%3Ad'], 'TARGET changes parsing' );

# croaking link handler
$b = beacon( \"#TARGET: f:{LABEL}\na:b|c:d", links => sub { die 'bad' } );
ok(! $b->parse );
ok( $b->lasterror =~ /^link handler died: bad/, 'dead link handler' );

# pre meta fields
$b = beacon( 't/beacon1.txt', 'pre' => { 'BAR' => 'doz', 'prefix' => 'y:' } );
is( $b->meta('bar'), 'doz', 'pre meta fields' );
is( $b->meta('prefix'), 'x:' );
# is( $b->line, 0 ); # 6

$b->parse( \"#PREFIX: z:" );
is( $b->meta('bar'), 'doz' );
is( $b->meta('prefix'), 'z:' );

$b->parse( \"#PREFIX: z:", pre => undef );
is( $b->meta('bar'), undef );
