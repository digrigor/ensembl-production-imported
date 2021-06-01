#!/usr/env perl
use v5.14.00;
use strict;
use warnings;
use Carp;
use autodie qw(:all);
use Readonly;
use Getopt::Long qw(:config no_ignore_case);
use Log::Log4perl qw( :easy ); 
Log::Log4perl->easy_init($WARN); 
my $logger = get_logger(); 
use Capture::Tiny ':all';

use Bio::EnsEMBL::Registry;
use Try::Tiny;

my @fields = qw(
BRC4.component
BRC4.organism_abbrev
species.scientific_name
species.strain
assembly.accession
);

###############################################################################
# MAIN
# Get command line args
my %opt = %{ opt_check() };

my $registry = 'Bio::EnsEMBL::Registry';

my $reg_path = $opt{registry};
$registry->load_all($reg_path);

my $sps = $registry->get_all_species();

my @genomes;
for my $sp (sort @$sps) {
  my $dbas;
  my %groups;
  $dbas = $registry->get_all_DBAdaptors($sp);
  %groups = map { $_->group => 1 } @$dbas;
  
  my $db = "";
  my $name = "";
  my ($core) = grep { $_->group eq 'core' } @$dbas;
  my $skip = 0;
  my %stats;

  if ($core) {
    try {
      my ($stdout, $stderr) = capture {
        $db = $core->dbc->dbname;
        my $genea = $core->get_GeneAdaptor();
        my $tra = $core->get_TranscriptAdaptor();
        my $meta = $registry->get_adaptor($sp, "core", "MetaContainer");
        
        for my $key (@fields) {
          $stats{$key} = get_meta_value($meta, $key);
        }
      };
      $core->dbc->disconnect_if_idle();
      print($stdout);
      
      print STDERR $stderr if $opt{debug};
    } catch {
      warn("Error: can't use core for $sp: $_");
    };
  }

  # To print
  push @genomes, \%stats;
}

for my $genome (sort {
    $a->{'BRC4.component'} cmp $b->{'BRC4.component'}
      or $a->{'species.scientific_name'} cmp $b->{'species.scientific_name'}
      or $a->{'BRC4.organism_abbrev'} cmp $b->{'BRC4.organism_abbrev'}
  } @genomes) {
  say join("\t", map { $genome->{$_} // "" } @fields);
}

sub get_meta_value {
  my ($meta, $key) = @_;
  my ($value) = @{ $meta->list_value_by_key($key) };
  return $value;
}

###############################################################################
# Parameters and usage
sub usage {
  my $error = shift;
  my $help = '';
  if ($error) {
    $help = "[ $error ]\n";
  }
  $help .= <<'EOF';
    Show species metadata in a registry (especially for bRC4)

    --registry <path> : Ensembl registry

    --species <str>   : production_name from core db
    --organism <str>  : organism_abbrev from brc4
    
    --help            : show this help message
    --verbose         : show detailed progress
    --debug           : show even more information (for debugging purposes)
EOF
  print STDERR "$help\n";
  exit(1);
}

sub opt_check {
  my %opt = ();
  GetOptions(\%opt,
    "registry=s",
    "species=s",
    "organism=s",
    "help",
    "verbose",
    "debug",
  );

  usage("Registry needed") if not $opt{registry};
  usage()                if $opt{help};
  Log::Log4perl->easy_init($INFO) if $opt{verbose};
  Log::Log4perl->easy_init($DEBUG) if $opt{debug};
  return \%opt;
}

__END__

