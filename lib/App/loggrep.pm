package App::loggrep;

# ABSTRACT: quickly find relevant lines in a log searching by date

use strict;
use warnings;

use Tie::File;
use Date::Parse qw(str2time);

=method new

  App::loggrep->new( $log, $opt );

Constructs an uninitialized grepper. The C<$log> file is a file name and the
C<$opt> parameter a L<Getopt::Long::Descriptive::Opts> object.

=cut

sub new {
   my ( $class, $log, $opt ) = @_;
   bless { filename => $log, options => $opt }, $class;
}

=method init

Validates all parameters and compiles regexes, returning a list of error
messages.

=cut

sub init {
   my $self = shift;
   my @errors;
   my $filename = $self->{filename};
   my @lines;
   my $opt = delete $self->{options};
   {
      unless ( defined $filename ) {
         push @errors, 'no log file provided';
         last;
      }
      unless ( -e $filename ) {
         push @errors, "file $filename does not exist";
         last;
      }
      if ( -d $filename ) {
         push @errors, "$filename is a directory";
         last;
      }
      unless ( -r $filename ) {
         push @errors, "cannot read $filename";
         last;
      }
      tie @lines, 'Tie::File', $filename or push @errors, $!;
      $self->{lines} = \@lines;
   }
   $self->{date} = _make_rx( $opt->date, \@errors, 'date' );
   my @inclusions = @{ $opt->include // [] };
   $_ = _make_rx( $_, \@errors, 'inclusion' ) for @inclusions;
   $self->{include} = \@inclusions;
   my @exclusions = @{ $opt->exclude // [] };
   $_ = _make_rx( $_, \@errors, 'exclude' ) for @exclusions;
   $self->{exclude} = \@exclusions;
   my $start = $opt->start;

   if ($start) {
      my $s = str2time $start;
      push @errors, "cannot parse start time: $start" unless $s;
      $self->{start} = $s;
   }
   my $end = $opt->end;
   if ($end) {
      my $s = str2time $end;
      push @errors, "cannot parse end time: $end" unless $s;
      $self->{end} = $s;
   }
   push @errors, 'you are not filtering at all'
     unless @inclusions || @exclusions || $start || $end;
   $self->{warn} = $opt->warn;
   $self->{die}  = $opt->die;
   return @errors;
}

# parse a regular expression parameter, registering any errors
sub _make_rx {
   my ( $rx, $errors, $type ) = @_;
   unless ($rx) {
      push @$errors, "inadequate $type pattern";
      return;
   }
   eval { $rx = qr/$rx/ };
   if ($@) {
      push @$errors, "bad $type regex: $rx; error: $@";
      return;
   }
   return $rx;
}

=method grep

Perform the actual grep. Lines are printed to STDOUT.

=cut

sub grep {
   my $self = shift;
   my ( $start, $end, $lines, $include, $exclude, $date, $warn, $die ) =
     @$self{qw(start end lines include exclude date warn die)};
   return unless @$lines;
   my $quiet = !( $warn || $die );
   my $gd = sub {
      my $l = shift;
      if ( $l =~ $date ) {
         my $t = str2time $1;
         return $t if $t;
      }
      return if $quiet;
      my $msg = qq(could not find date in "$l");
      if ($warn) {
         print STDERR $msg, "\n";
         return;
      }
      print STDERR $msg, "\n";
      exit;
   };
   my $i = 0;
   my $time_filter = $start || $end;
   if ($time_filter) {
      my ( $t1, $t2, $j );
      for ( 0 .. $#$lines ) {
         $t1 = $gd->( $lines->[$_] );
         $j  = $_;
         last if $t1;
      }
      return unless $t1;
      for ( reverse $j .. $#$lines ) {
         $t2 = $gd->( $lines->[$_] );
         last if $t2;
      }
      $start = $t1 unless $start;
      $end   = $t2 unless $end;
      return unless $end >= $t1;
      return unless $start <= $t2;
      $i = _get_start( $lines, $start, $t1, $t2, $gd );
   }
   my @include = @$include;
   my @exclude = @$exclude;
 OUTER: while ( my $line = $lines->[ $i++ ] ) {
      if ($time_filter) {
         my $t = $gd->($line);
         next unless $t;
         last if $t > $end;
         next if $t < $start;
      }
      my $good = !@include;
      for (@include) {
         if ( $line =~ $_ ) {
            $good = 1;
            last;
         }
      }
      next unless $good;
      for (@exclude) {
         next OUTER if $line =~ $_;
      }
      print $line, "\n";
   }
}

# find the log line to begin grepping at
sub _get_start {
   my ( $lines, $start, $t1, $t2, $gd ) = @_;
   return 0 if $start <= $t1;
   my $lim = $#$lines;
   my ( $s, $e ) = ( [ 0, $t1 ], [ $lim, $t2 ] );
   my $last = -1;
   {
      my $i = _guess( $s, $e, $start );
      return $i if $i == $s->[0];
      my $rev = $last == $i;
      $last = $i;
      my $t;
      {
         $t = $gd->( $lines->[$i] );
         unless ($t) {
            $i += $rev ? -1 : 1;
            return 0 unless $i;
            return $lim if $i > $lim;
            redo;
         }
      }
      return $i if $t == $start;
      if ( $t < $start ) {
         $s = [ $i, $t ];
      }
      else {
         $e = [ $i, $t ];
      }
      return $i - 1 if $s->[0] == $e->[0];
      redo;
   }
}

# estimate the next log line to try
sub _guess {
   my ( $s, $e, $start ) = @_;
   my $delta = $start - $s->[1];
   return $s->[0] unless $delta;
   my $diff = $e->[1] - $s->[1];
   my $offset = int( ( $e->[0] - $s->[0] ) * $delta / $diff );
   return $s->[0] + $offset;
}

1;
