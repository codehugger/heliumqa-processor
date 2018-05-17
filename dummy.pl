#!/usr/bin/perl

# Strict and warnings are recommended.
use strict;
use warnings;

use File::Copy;

my ($source) = @ARGV;

if (not defined $source) {
  die "Need source\n";
}
else {
  print "Processing '$source'\n";

  # Create results folder
  my $resultsdir = "$source/results";
  mkdir $resultsdir;

  # Save results.json
  open(my $fhresult, '>', "$resultsdir/results.json") or die "Could not open file '$resultsdir/results.json' $!";
  print $fhresult '
  { "groups": [{ "key": "dummy_group","label": "Dummy Group","results": [{ "key": "dummy_file","label": "Dummy File","type" : "file","file_path" : "examples/sample.png" }] }] }';
  close $fhresult;

  # "process" files
  my $examplesfiledir = "examples";
  my $filename = "sample.png";
  print "$filename\n";
  copy("$examplesfiledir/$filename","$resultsdir/$filename") or die "Copy failed: $!";

  # Signal that the processing is complete
  open(my $fhtimestamp, '>', "$resultsdir/timestamp") or die "Could not open file '$source/timestamp' $!";
  print $fhtimestamp localtime;
  close $fhtimestamp;

  exit;
}
