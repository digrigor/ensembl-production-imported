=head1 LICENSE

Ensembl
Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2021] EMBL-European Bioinformatics Institute

This product includes software developed at:

EMBL-European Bioinformatics Institute
Wellcome Trust Sanger Institute

=cut

=pod

=head1 NAME

  Bio::EnsEMBL::EGPipeline::PipeConfig::MapPHI_base_conf

=head1 SYNOPSIS


  init_pipeline.pl Bio::EnsEMBL::EGPipeline::PipeConfig::MapPHI_base_conf  -pipeline_url $EHIVE_URL  -registry $REGISTRY_FILE -blast_db_dir $BLAST_DB_DIRECTORY -input_file $INPUT_ROTHAMSTED_FILE -hive_force_init 1

  runWorker.pl -url $EHIVE_URL

  runWorker.pl -url $EHIVE_URL --reg_conf $REGISTRY_FILE



=head1 DESCRIPTION

  This is an example pipeline put together from five basic building blocks:

  Analysis_1: JobFactory.pm is used to turn the list of files in a given directory into jobs

      these jobs are sent down the branch #2 into the second analysis

  Analysis_2: JobFactory.pm is used to run a wc command to determine the size of a file
              (and format the output with sed), then capture the command's object, putting
              the file size into a parameter for later use.

  Analysis_3: SystemCmd.pm is used to run these compression/decompression jobs in parallel.

  Analysis_4: JobFactory.pm is used to run a wc command to determine the size of a file
              (and format the output with sed), then capture the command's object, putting
              the file size into a parameter for later use.

  Analysis_5: SystemCmd.pm is used to run the notify-send command, displaying a message on the screen.

=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <https://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <https://www.ensembl.org/Help/Contact>.

=cut

package Bio::EnsEMBL::EGPipeline::PipeConfig::MapPHI_base_conf;


use strict;
use warnings;

## EG common configuration (mostly resource classes)
use base ('Bio::EnsEMBL::EGPipeline::PipeConfig::EGGeneric_conf');

## Hive common configuration (every hive pipeline needs this, i.e for using "INPUT_PLUS()")
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;

#defines default values for some of the parameters
sub default_options {
  my ($self) = @_;
  return {
    %{$self->SUPER::default_options},
      obo_file => '',
  };
}

#Defines which parameters are required from the user command's line
sub pipeline_wide_parameters {
  my ($self) = @_;
  return {
     %{$self->SUPER::pipeline_wide_parameters},

    'inputfile'             => $self->o('inputfile'),
    'core_db_url'	    => $self->o('core_db_url'), 
    'registry'		    => $self->o('reg_file'),
    'source_db'		    => $self->o('source_db')
  };
}

=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.

=cut

sub pipeline_analyses {
  my ($self) = @_;
  
  return [
    { 
      -logic_name => 'interaction_keys',
      -module     => 'ensembl.microbes.runnables.PHIbase_2.InteractionKeys',
      -language   => 'python3',
      -input_ids  => [{
                       'inputfile' => $self->o('inputfile'),
		       'registry'  => $self->o('reg_file'),
		       'source_db' => $self->o('source_db'),
                     }],
      -parameters => {
                       registry   => '#registry#',
		       inputfile  => '#inputfile#',
		       source_db  => '#source_db#',
		       obo_file   => $self->o('obo_file'),
                      },
      -flow_into    => {
                        1 => {'load_ontologies' => INPUT_PLUS()},
                       },
    },
    {
      -logic_name => 'load_ontologies',
      -module     => 'ensembl.microbes.runnables.PHIbase_2.OntologiesLoader',
      -language   => 'python3',
      -flow_into    => {
                         1 => 'input_file',
                        },
    },
    {
      -logic_name => 'input_file',
      -module     => 'ensembl.microbes.runnables.PHIbase_2.FileReader',
      -language   => 'python3',
      -parameters => {
		       delimiter => ',',
		       column_names => 1,
                      },
      -flow_into    => {
			2 => {'meta_ensembl_reader' => INPUT_PLUS() },
		       },
    },
    { 
      -logic_name => 'meta_ensembl_reader',
      -module     => 'ensembl.microbes.runnables.PHIbase_2.MetaEnsemblReader',
      -language   => 'python3',
      -flow_into    => {
                        1 => WHEN ("#failed_job# eq '' " => { 'ensembl_core_reader' => INPUT_PLUS() }),
                        -3 => WHEN ("#failed_job# ne '' "  => ['failed_entries']),
			},
    },
    {  
       -logic_name => 'ensembl_core_reader',
       -module     => 'ensembl.microbes.runnables.PHIbase_2.EnsemblCoreReader',
       -language   => 'python3',
       -flow_into    => {
                        1 => WHEN ("#failed_job# eq '' " => { 'sequence_finder' => INPUT_PLUS() }),
			-3 => WHEN ("#failed_job# ne '' "  => ['failed_entries']),
		        },
    },
    { 
       -logic_name => 'sequence_finder',
       -module     => 'ensembl.microbes.runnables.PHIbase_2.SequenceFinder',
       -language   => 'python3',
       -flow_into    => {
                        1 => WHEN ("#failed_job# eq '' " => { 'interactor_data_manager' => INPUT_PLUS() }),
                        -3 => WHEN ("#failed_job# ne '' "  => ['failed_entries']),
		        },
    },
    {
      -logic_name => 'interactor_data_manager',
      -module     => 'ensembl.microbes.runnables.PHIbase_2.InteractorDataManager',
      -language   => 'python3',
      -flow_into    => {
                        -3 => WHEN ("#failed_job# ne '' "  => ['failed_entries']),
                         1 => WHEN ("#failed_job# eq '' " => { 'interaction_table' => INPUT_PLUS() }),
                        },
    },
    {
      -logic_name => 'interaction_table',
      -module     => 'ensembl.microbes.runnables.PHIbase_2.InteractionTable',
      -language   => 'python3',
      -flow_into    => {
                        -3 => WHEN ("#failed_job# ne '' "  => ['failed_entries']),
                         1 => WHEN ("#failed_job# eq '' " => { 'db_writer' => INPUT_PLUS() }),
                        },
    },
    { 
      -logic_name => 'failed_entries',
      -module     => 'ensembl.microbes.runnables.PHIbase_2.FailedEntries',
      -language   => 'python3',
    },
    { 
      -logic_name => 'db_writer',
      -module     => 'ensembl.microbes.runnables.PHIbase_2.DBwriter',
      -language   => 'python3',
    }
  ];
}

sub hive_meta_table {
  my ($self) = @_;
  return {
    %{$self->SUPER::hive_meta_table},
    'hive_use_param_stack'  => 1, #Jobs see parameters from their ascendants without needing INPUT_PLUS()
  };
}


sub resource_classes {
  my ($self) = @_;
  my $reg_requirement = '--reg_conf ' . $self->o('reg_file'); #pass registry on to the workers without needing to specify it with the beekeeper
  return {
    %{$self->SUPER::resource_classes},  # inherit 'default' from the parent class
     };

}

1;

