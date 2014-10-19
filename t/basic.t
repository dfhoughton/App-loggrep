use strict;
use warnings;
use App::loggrep;

use Test::More;
use File::Temp qw(tempfile);
use Capture::Tiny qw(capture_stdout);

{

   package Opty;

   sub AUTOLOAD {
      ( my $name = our $AUTOLOAD ) =~ s/.*:://;
      no strict 'refs';
      *$AUTOLOAD = sub { shift->{$name} };
      goto &$AUTOLOAD;
   }
}

my $data = <<'END';
a
b
c
d
9:12:00
e
f
9:12:01
9:12:10
9:12:20
9:12:30
9:12:40
9:12:45
9:12:50
g
h
END

my ( $fh, $filename ) = tempfile();
END { unlink $filename }
print $fh $data;
close $fh;

my %basic = (
   start => '9:12:01',
   end   => '9:12:01',
   date  => '^(\d++(?::\d++)*+)',
   log   => $filename
);

my $opts = bless {%basic }, 'Opty';
my $grepper = App::loggrep->new( $filename, $opts );
$grepper->init;
my $stdout = capture_stdout { $grepper->grep };
$stdout =~ s/^\s+|\s+$//g;
is $stdout, '9:12:01', "single line exact times";

$opts = bless {%basic, before => 1 }, 'Opty';
$grepper = App::loggrep->new( $filename, $opts );
$grepper->init;
$stdout = capture_stdout { $grepper->grep };
$stdout =~ s/^\s+|\s+$//g;
like $stdout, qr/^f/, "single line exact times; --before 1";

$opts = bless {%basic, before => 2 }, 'Opty';
$grepper = App::loggrep->new( $filename, $opts );
$grepper->init;
$stdout = capture_stdout { $grepper->grep };
$stdout =~ s/^\s+|\s+$//g;
like $stdout, qr/^e/, "single line exact times; --before 2";



done_testing();

