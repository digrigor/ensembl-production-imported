#!env python3

from redminelib import Redmine
import argparse
import os, json, re, time
import requests
import xml.etree.ElementTree as ET
 
url = 'https://redmine.apidb.org'
default_fields = dict(
        status_name = 'Data Processing (EBI)',
        cf_17 = "Data Processing (EBI)",
        )
insdc_pattern = "^GC[AF]_\d{9}(\.\d+)?$"
accession_api_url = "https://www.ebi.ac.uk/ena/browser/api/xml/%s"
veupathdb_id = 1976

def retrieve_rnaseq_datasets(redmine, output_dir, build=None):
    """
    Get RNA-Seq metadata from Redmine, store them in json files.
    Each issue/dataset is stored as one file in the output dir
    """
    issues = get_issues(redmine, "RNA-seq", build)
    if not issues:
        print("No files to create")
        return
    
    # Create the output dir
    try:
        os.mkdir(output_dir)
    except:
        pass
    
    for issue in issues:
        dataset = parse_dataset(issue)
        if not dataset:
            print("Skipped issue %d (%s). Not enough metadata." % (issue.id, issue.subject))
            continue

        try:
            component = dataset["component"]
            organism = dataset["species"]
            dataset_name = dataset["name"]
            file_name = organism + "_" + dataset_name + ".json"
            dataset_file = output_dir + "/" + file_name
            print(dataset_file)
            f = open(dataset_file, "w")
            json.dump(dataset, f, indent=True)
            f.close()
        except Exception as error:
            print("Skipped issue %d (%s). %s." % (issue.id, issue.subject, error))
            pass
 
def parse_dataset(issue):
    """
    Extract RNA-Seq dataset metadata from a Redmine issue
    Return a nested dict
    """
    print("Parsing issue %s (%s)" % (issue.id, issue.subject))
    customs = get_custom_fields(issue)
    dataset = {
            "component": "",
            "species": "",
            "name": "",
            "runs": [],
            }

    dataset["component"] = get_custom_value(customs, "Component DB")
    dataset["species"] = get_custom_value(customs, "Organism Abbreviation")
    dataset["name"] = get_custom_value(customs, "Internal dataset name")
    
    # Get samples/runs
    samples_str = get_custom_value(customs, "Sample Names")
    try:
        samples = parse_samples(samples_str)
        dataset["runs"] = samples
        return dataset
    except Exception as e:
        print("Errors: %s" % e)
        return

def parse_samples(sample_str):
    samples = []
    
    # Parse each line
    lines = sample_str.split("\n")
    for line in lines:
        line = line.strip()
        # Assuming only one :
        parts = line.split(":")
        if len(parts) == 2:
            sample_name = parts[0].strip()
            accessions_str = parts[1].strip()
            accessions = [x.strip() for x in accessions_str.split(",")]
            sample = {
                    "name": sample_name,
                    "accessions": accessions
                    }
            samples.append(sample)
        elif len(parts) > 2:
            raise Exception("More than two parts (sample name may have a ':' in it)")
        else:
            raise Exception("Sample line doesn't have 2 parts: '%s'" % line)
    
    return samples

def get_custom_fields(issue):
    """
    Put all Redmine custom fields in a dict instead of an array
    Return a dict
    """
    
    cfs = {}
    for c in issue.custom_fields:
        cfs[c["name"]] = c
    return cfs

def get_custom_value(customs, key):
   
    try:
        value = customs[key]["value"]
        if isinstance(value, list):
            if len(value) == 1:
                value = value[0]
            elif len(components) > 1:
                raise Exception("More than 1 values for key %s" % (key))
        return value
    except:
        print("No field %s" % (key))
        return ""
    

def get_issues(redmine, datatype, build=None):
    """
    Retrieve all issue for new genomes, be they with or without gene sets
    Return a Redmine ResourceSet
    """
    
    other_fields = { "cf_94" : datatype }
    if build:
        version_id = get_version_id(redmine, build)
        other_fields["fixed_version_id"] = version_id

    return list(get_ebi_issues(redmine, other_fields))

def get_version_id(redmine, build):
    """
    Given a build number, get the version id for it
    """
    versions = redmine.version.filter(project_id=veupathdb_id)
    version_name = "Build " + str(build)
    version_id = [version.id for version in versions if version.name == version_name]
    return version_id
    
def get_ebi_issues(redmine, other_fields=dict()):
    """
    Get EBI issues from Redmine, add other fields if provided
    Return a Redmine ResourceSet
    """

    # Other fields replace the keys that already exist in default_fields
    search_fields = { **default_fields, **other_fields }
    
    return redmine.issue.filter(**search_fields)
    

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Retrieve metadata from Redmine')
    
    parser.add_argument('--key', type=str, required=True,
                help='Redmine authentification key')
    parser.add_argument('--output_dir', type=str, required=True,
                help='Output_dir')
    # Choice
    parser.add_argument('--get', choices=['rnaseq', 'dnaseq'], required=True,
                help='Get rnaseq, or dnaseq issues')
    # Optional
    parser.add_argument('--build', type=int,
                help='Restrict to a given build')
    args = parser.parse_args()
    
    # Start Redmine API
    redmine = Redmine(url, key=args.key)
    
    # Choose which data to retrieve
    if args.get == 'rnaseq':
        retrieve_rnaseq_datasets(redmine, args.output_dir, args.build)
    elif args.get == 'dnaseq':
        retrieve_dnaseq_datasets(redmine, args.output_dir, args.build)
    else:
        print("Need to say what data you want to --get: rnaseq? dnaseq?")

if __name__ == "__main__":
    main()
