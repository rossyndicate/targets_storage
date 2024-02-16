#' @title Find bad site identifiers
#' 
#' @description
#' Function to check sites for identifier names that are likely to cause 
#' problems when downloading data from WQP by siteid. Some site identifiers
#' contain characters that cannot be parsed by WQP, including "/". This function
#' identifies and subsets sites with potentially problematic identifiers.
#' 
#' @param sites data frame containing the site identifiers. Must contain
#' column `MonitoringLocationIdentifier`.
#' 
#' @returns 
#' Returns a data frame where each row represents a site with a problematic
#' identifier, indicated by the new column `site_id`. All other columns within
#' `sites` are retained. Returns an empty data frame if no problematic site
#' identifiers are found.
#' 
#' @examples 
#' siteids <- data.frame(MonitoringLocationIdentifier = 
#'                         c("USGS-01573482","COE/ISU-27630001"))
#' identify_bad_ids(siteids)
#' 
identify_bad_ids <- function(sites){
  
  # Check that string format matches regex used in WQP
  sites_bad_ids <- sites %>%
    rename(site_id = MonitoringLocationIdentifier) %>% 
    mutate(site_id_regex = str_extract(site_id, "[\\w]+.*[\\S]")) %>%
    filter(site_id != site_id_regex) %>%
    select(-site_id_regex)
  
  return(sites_bad_ids)
}



#' @title Download data from the Water Quality Portal
#' 
#' @description 
#' Function to pull WQP data given a dataset of site ids and/or site coordinates.
#'  
#' @param site_counts_grouped data frame containing a row for each site. Columns 
#' contain the site identifiers, the total number of records, and an assigned
#' download group. Must contain columns `site_id` and `pull_by_id`, where
#' `pull_by_id` is logical and indicates whether data should be downloaded
#' using the site identifier or by querying a small bounding box around the site.
#' @param char_names vector of character strings indicating which WQP 
#' characteristic names to query.
#' @param wqp_args list containing additional arguments to pass to whatWQPdata(),
#' defaults to NULL. See https://www.waterqualitydata.us/webservices_documentation 
#' for more information.  
#' @param max_tries integer, maximum number of attempts if the data download 
#' step returns an error. Defaults to 3.
#' @param verbose logical, indicates whether messages from {dataRetrieval} should 
#' be printed to the console in the event that a query returns no data. Defaults 
#' to FALSE. Note that `verbose` only handles messages, and {dataRetrieval} errors 
#' or warnings will still get passed up to `fetch_wqp_data`. 
#' 
#' @returns
#' Returns a data frame containing data downloaded from the Water Quality Portal, 
#' where each row represents a unique data record.
#' 
#' @examples
#' site_counts <- data.frame(site_id = c("USGS-01475850"), pull_by_id = c(TRUE))
#' fetch_wqp_data(site_counts, 
#'               "Temperature, water", 
#'               wqp_args = list(siteType = "Stream"))
#' 
fetch_wqp_data <- function(site_counts_grouped, char_names, wqp_args = NULL, 
                           max_tries = 3, verbose = FALSE){
  
  message(sprintf("Retrieving WQP data for %s sites in group %s, %s",
                  nrow(site_counts_grouped), unique(site_counts_grouped$download_grp), 
                  char_names))
  
  # Define arguments for readWQPdata
  # sites with pull_by_id = FALSE cannot be queried by their site
  # identifiers because of undesired characters that will cause the WQP
  # query to fail. For those sites, query WQP by adding a small bounding
  # box around the site(s) and including bBox in the wqp_args.
  if(unique(site_counts_grouped$pull_by_id)){
    wqp_args_all <- c(wqp_args, 
                      list(siteid = site_counts_grouped$site_id,
                           characteristicName = c(char_names)))
  } else {
    wqp_args_all <- c(wqp_args, 
                      list(bBox = create_site_bbox(site_counts_grouped),
                           characteristicName = c(char_names)))
  }
  
  # Define function to pull data, retrying up to the number of times
  # indicated by `max_tries`
  pull_data <- function(x){
    retry(readWQPdata(x),
          when = "Error:", 
          max_tries = max_tries)
  }
  
  # Now pull the data. If verbose == TRUE, print all messages from dataRetrieval,
  # otherwise, suppress messages.
  if(verbose) {
    wqp_data <- pull_data(wqp_args_all)
  } else {
    wqp_data <- suppressMessages(pull_data(wqp_args_all))
  }
  
  # We applied special handling for sites with pull_by_id = FALSE (see comments
  # above). Filter wqp_data to only include sites requested in site_counts_grouped
  # in case our bounding box approach picked up any additional, undesired sites. 
  # In addition, some records return character strings when we expect numeric 
  # values, e.g. when "*Non-detect" appears in the "ResultMeasureValue" field. 
  # For now, consider all columns to be character so that individual data
  # frames returned from fetch_wqp_data can be joined together. 
  wqp_data_out <- wqp_data %>%
    filter(MonitoringLocationIdentifier %in% site_counts_grouped$site_id) %>%
    mutate(across(everything(), as.character))
  
  return(wqp_data_out)
}
