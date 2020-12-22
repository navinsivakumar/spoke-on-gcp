# spoke-on-gcp

Run Spoke on GCP with Terraform.

This is very much a work in progress. Currently, it deploys a very simple Spoke
service on Cloud Run backed by a Cloud SQL Postgres instance using local auth.

## Usage

Note that, much like the Terraform configuration itself, these instructions are
very much a work in progress.

### Prerequisites

1.  Download and install the
    [Google Cloud SDK](https://cloud.google.com/sdk/docs/install).
1.  Download and install [Terraform](https://www.terraform.io/downloads.html).

### Deploying Spoke

1.  Create (or choose an existing) GCP project where you plan to deploy Spoke:
    ```shell
    $ PROJECT_ID=<your GCP project ID>
    ```
    1.  You will need to enable billing on the project. Spoke instances do not
        fall within free tier limits and will incur charges.
1.  Set your default project for `gcloud`:
    ```shell
    $ gcloud config set project ${PROJECT_ID}
    ```
1.  Configure your GCP default application credentials:
    ```shell
    $ gcloud auth application-default login
    ```
1.  Build and push a Spoke container image to Container Registry:
    ```shell
    # From the root directory of your Spoke repository:
    Spoke$ IMAGE_NAME=spoke
    Spoke$ gcloud builds submit --tag gcr.io/${PROJECT_ID}/${IMAGE_NAME}
    ```
    1.  Note that there are some code changes required in order for Spoke to run
        on Cloud Run. You can find experimental code with the necessary changes
        at https://github.com/navinsivakumar/Spoke/tree/gcp
1.  Run Terraform:
    ```shell
    # From the root directory of your spoke-on-gcp repository:
    # us-central1, us-east1, or us-west1 should give the lowest charges
    spoke-on-gcp$ REGION=us-central1
    spoke-on-gcp$ terraform init
    spoke-on-gcp$ CONTAINER_URL=gcr.io/${PROJECT_ID}/${IMAGE_NAME}
    # Optionally run `terraform plan` with the same flags as below to preview
    # changes.
    spoke-on-gcp$ terraform apply -var="project=${PROJECT_ID}" -var="region=${REGION}" -var="spoke_container=gcr.io/${PROJECT_ID}/${IMAGE_NAME}"
    ```
1.  The output from the `terraform apply` command will show the URL that you can
    visit to use your Spoke instance. You can also view the URL again by running
    ```shell
    spoke-on-gcp$ terraform output spoke_url
    ```

### Deleting your deployment

You can delete your instance with `terraform destroy`:
```shell
# Optionally run `terraform plan -destroy` with the same flags to preview
# changes.
spoke-on-gcp$ terraform destroy -var="project=${PROJECT_ID}" -var="region=${REGION}" -var="spoke_container=gcr.io/${PROJECT_ID}/${IMAGE_NAME}"
```
