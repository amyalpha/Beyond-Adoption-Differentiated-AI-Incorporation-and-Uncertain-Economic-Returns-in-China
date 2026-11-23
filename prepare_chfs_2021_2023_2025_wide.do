version 16.0
clear all
set more off

/*
    CHFS 2021, 2023, and 2025: preparation of a person-level wide file

    Design
    ------
    1. Prepare and rename variables separately in each survey wave.
    2. Verify that hhid + pline uniquely identify a person in each wave.
    3. Merge, rather than append, the three wave files.
    4. Preserve wave-specific tracking status and survey weights.
    5. Construct availability indicators without deleting incomplete cases.

    Important
    ---------
    - hhid + pline are the merge keys.
    - pline is a personal identifier; do not restrict the data to pline == 1.
    - istracking is tracking status; it is not a merge key.
    - The 2021, 2023, and 2025 surveys report annual income for 2020,
      2022, and 2024, respectively.
    - GAI and PAI samples are always defined independently.
    - This file does not run any regression and does not impose a final
      complete-case sample.
*/


*--------------------------------------------------------------------*
* 0. EDIT THE PATHS AND SOURCE FILE NAMES
*--------------------------------------------------------------------*

global project_root "REPLACE_WITH_THE_PROJECT_FOLDER"
global data_dir     "$project_root"
global output_dir   "$project_root/prepared_data"

local file2021 "$data_dir/2021.dta"
local file2023 "$data_dir/2023.dta"
local file2025 "$data_dir/2025.dta"

capture mkdir "$output_dir"

local prepared2021 "$output_dir/chfs2021_prepared.dta"
local prepared2023 "$output_dir/chfs2023_prepared.dta"
local prepared2025 "$output_dir/chfs2025_prepared.dta"
local widefile     "$output_dir/chfs_2021_2023_2025_wide.dta"

foreach y in 2021 2023 2025 {
    capture confirm file "`file`y''"
    if _rc {
        display as error "Cannot find the `y' source file: `file`y''"
        display as error "Edit project_root and the three file names above."
        exit 601
    }
}


*--------------------------------------------------------------------*
* 1. PROGRAM TO PREPARE ONE WAVE
*--------------------------------------------------------------------*

capture program drop prepare_wide_wave

program define prepare_wide_wave
    version 16.0
    syntax using/, SURVEYYEAR(integer) SUFFIX(name) SAVEAS(string)

    use `"`using'"', clear

    * If the source is Stata-mi data, use the original-data record m=0.
    * If it is ordinary data, the captured command makes no change.
    capture mi extract 0, clear

    * Required person identifiers and tracking status.
    foreach v in hhid pline istracking {
        capture confirm variable `v'
        if _rc {
            display as error "Required variable `v' is absent from `using'."
            exit 111
        }
    }

    * Required income variables constructed before this file is run.
    foreach v in total_income total_reported_income {
        capture confirm variable `v'
        if _rc {
            display as error "Required variable `v' is absent from `using'."
            exit 111
        }
    }

    * The 2023 cognition measures are required for the longitudinal model.
    if `surveyyear' == 2023 {
        foreach v in AIawareness familiarAI useAI birthy {
            capture confirm variable `v'
            if _rc {
                display as error "Required 2023 variable `v' is absent."
                exit 111
            }
        }
    }

    * The reconstructed 2025 use indicators are required outcomes.
    if `surveyyear' == 2025 {
        foreach v in gai_use_raw pai_use_raw {
            capture confirm variable `v'
            if _rc {
                display as error "Required 2025 variable `v' is absent."
                exit 111
            }
        }
    }

    * Standardize hhid as a trimmed string in every source file.
    * This does not discard leading zeroes already stored in string IDs.
    capture confirm string variable hhid
    if _rc {
        tostring hhid, replace format(%18.0f)
    }
    replace hhid = strtrim(hhid)

    * Standardize pline as numeric.
    capture confirm numeric variable pline
    if _rc {
        capture destring pline, replace
        if _rc {
            display as error "pline cannot be converted to numeric in `surveyyear'."
            exit 109
        }
    }

    * Standardize tracking status as numeric.
    capture confirm numeric variable istracking
    if _rc {
        capture destring istracking, replace
        if _rc {
            display as error "istracking cannot be converted to numeric in `surveyyear'."
            exit 109
        }
    }

    drop if missing(hhid) | missing(pline)

    * Do not remove newly sampled respondents here.
    * Tracking restrictions are defined transparently after the merge.

    capture isid hhid pline
    if _rc {
        display as error "hhid + pline are not unique in the `surveyyear' file."
        duplicates report hhid pline
        exit 459
    }

    * Common variables retained whenever they exist in a wave.
    * The list is written as source-name / harmonized-stem pairs.
    local common_map                                               ///
        A1013                ai_respondent_pline                    ///
        birthy                birthyear                            ///
        sex                   sex                                  ///
        marriage              marriage                             ///
        edulev                education                            ///
        partym                party                                ///
        hukoutype             hukou                                ///
        hknliv                hknliv                               ///
        hukouknlv             hukouknlv                            ///
        rural                 rural                                ///
        region                region                               ///
        city_level            city_level                           ///
        prov_code             province                             ///
        city_code             city                                 ///
        hhsize                hhsize                               ///
        nadult                nadult                               ///
        nchild                nchild                               ///
        eqscale               eqscale                              ///
        total_income          hh_income                            ///
        total_consump         hh_consumption                       ///
        eqincome              eq_income                            ///
        eqincome1             eq_income_alt                        ///
        havejob               havejob                              ///
        occupation            occupation                           ///
        industry              industry                             ///
        empsector             empsector                            ///
        jobf                  job_features                         ///
        workmth               workmonths                           ///
        workday               workdays                             ///
        workhor               workhours                            ///
        worktime              worktime                             ///
        main_work_type        main_work_type                       ///
        income_sample         income_sample                        ///
        main_work_income      main_work_income                     ///
        main_work_comp        main_work_comp                       ///
        has_other_job         other_job                            ///
        job_arrangement       job_arrangement                      ///
        other_job_income      other_job_income                     ///
        total_work_income     total_work_income                    ///
        total_work_comp       total_work_comp                      ///
        total_reported_income ind_income                           ///
        main_income_imputed   main_income_imputed                  ///
        main_comp_imputed     main_comp_imputed                    ///
        other_income_imputed  other_income_imputed                 ///
        total_income_imputed  ind_income_imputed                   ///
        total_comp_imputed    ind_comp_imputed                     ///
        havecpt               have_computer                        ///
        havephone             have_phone                           ///
        phonevalue            phone_value                          ///
        cptvalue              computer_value

    while `"`common_map'"' != "" {
        gettoken old  common_map : common_map
        gettoken stem common_map : common_map

        capture confirm variable `old'
        if !_rc {
            capture confirm variable `stem'_`suffix'
            if !_rc {
                display as error "Target variable `stem'_`suffix' already exists."
                exit 110
            }
            rename `old' `stem'_`suffix'
        }
    }

    * Preserve tracking status with an explicit wave suffix.
    rename istracking istracking_`suffix'

    * Household-weight aliases differ across delivered wave files.
    local hh_weight_found 0

    capture confirm variable weight_hh
    if !_rc {
        rename weight_hh household_weight_`suffix'
        local hh_weight_found 1
    }

    if `hh_weight_found' == 0 {
        capture confirm variable wgt_hh
        if !_rc {
            rename wgt_hh household_weight_`suffix'
            local hh_weight_found 1
        }
    }

    if `hh_weight_found' == 0 {
        display as text "Note: no household weight was found in `surveyyear'."
    }

    * Individual-weight aliases differ across delivered wave files.
    local ind_weight_found 0

    capture confirm variable weight_ind
    if !_rc {
        rename weight_ind individual_weight_`suffix'
        local ind_weight_found 1
    }

    if `ind_weight_found' == 0 {
        capture confirm variable wgt_ind
        if !_rc {
            rename wgt_ind individual_weight_`suffix'
            local ind_weight_found 1
        }
    }

    if `ind_weight_found' == 0 {
        display as text "Note: no individual weight was found in `surveyyear'."
    }

    * 2023 AI cognition and prior-engagement variables.
    if `surveyyear' == 2023 {
        local ai2023_map                                      ///
            AIawareness ai_awareness                         ///
            familiarAI  ai_familiarity                       ///
            useAI       ai_use

        while `"`ai2023_map'"' != "" {
            gettoken old  ai2023_map : ai2023_map
            gettoken stem ai2023_map : ai2023_map
            rename `old' `stem'_`suffix'
        }
    }

    * 2025 general-purpose and professional AI measures.
    if `surveyyear' == 2025 {
        local ai2025_map                                          ///
            gai_use_raw           gai_use                         ///
            gai_named_count       gai_named_count                 ///
            gai_tool_count        gai_count                       ///
            gai_tool_cat          gai_breadth                     ///
            useAI_time            gai_time                        ///
            gai_aug_count         gai_aug_count                   ///
            gai_pressure_count    gai_pressure_count              ///
            gai_augmentation      gai_augmentation                ///
            gai_pressure          gai_pressure                    ///
            gai_other_impact      gai_other_impact                ///
            gai_no_impact         gai_no_impact                   ///
            gai_impact_cat        gai_impact                      ///
            gai_invalid_response  gai_invalid_response            ///
            gai_grok_only         gai_grok_only                   ///
            pai_use_raw           pai_use                         ///
            pai_named_count       pai_named_count                 ///
            pai_tool_count        pai_count                       ///
            pai_tool_cat          pai_breadth                     ///
            usePAI_time           pai_time                        ///
            pai_aug_count         pai_aug_count                   ///
            pai_pressure_count    pai_pressure_count              ///
            pai_augmentation      pai_augmentation                ///
            pai_pressure          pai_pressure                    ///
            pai_other_impact      pai_other_impact                ///
            pai_no_impact         pai_no_impact                   ///
            pai_impact_cat        pai_impact                      ///
            pai_invalid_response  pai_invalid_response            ///
            pai_early_count       pai_early_count                 ///
            pai_late_count        pai_late_count

        while `"`ai2025_map'"' != "" {
            gettoken old  ai2025_map : ai2025_map
            gettoken stem ai2025_map : ai2025_map

            capture confirm variable `old'
            if !_rc {
                rename `old' `stem'_`suffix'
            }
        }

    }

    * Retain only identifiers and variables explicitly harmonized above.
    keep hhid pline *_`suffix'

    order hhid pline istracking_`suffix', first
    sort hhid pline
    compress

    isid hhid pline
    save `"`saveas'"', replace

    display as result "Prepared `surveyyear' file saved to: `saveas'"
end


*--------------------------------------------------------------------*
* 2. PREPARE THE THREE WAVES SEPARATELY
*--------------------------------------------------------------------*

prepare_wide_wave using "`file2021'",                   ///
    surveyyear(2021) suffix(w21) saveas("`prepared2021'")

prepare_wide_wave using "`file2023'",                   ///
    surveyyear(2023) suffix(w23) saveas("`prepared2023'")

prepare_wide_wave using "`file2025'",                   ///
    surveyyear(2025) suffix(w25) saveas("`prepared2025'")


*--------------------------------------------------------------------*
* 3. MERGE 2023 AND 2025 BY hhid + pline
*--------------------------------------------------------------------*

use "`prepared2023'", clear
isid hhid pline

merge 1:1 hhid pline using "`prepared2025'",            ///
    generate(merge_w23_w25)

label define merge2325_lbl                               ///
    1 "2023 only"                                       ///
    2 "2025 only"                                       ///
    3 "Observed in 2023 and 2025", replace

label values merge_w23_w25 merge2325_lbl
label variable merge_w23_w25 "2023-2025 merge result"

gen byte observed_w23 = inlist(merge_w23_w25, 1, 3)
gen byte observed_w25 = inlist(merge_w23_w25, 2, 3)
gen byte linked_w23_w25 = merge_w23_w25 == 3

label variable observed_w23 "Observed in 2023"
label variable observed_w25 "Observed in 2025"
label variable linked_w23_w25 "Observed in both 2023 and 2025"

display as text "2023-2025 merge result:"
tabulate merge_w23_w25, missing


*--------------------------------------------------------------------*
* 4. ADD 2021 BY hhid + pline
*--------------------------------------------------------------------*

merge 1:1 hhid pline using "`prepared2021'",             ///
    generate(merge_w21)

label define merge21_lbl                                 ///
    1 "Absent from 2021"                                ///
    2 "2021 only"                                       ///
    3 "Observed in 2021 and a later wave", replace

label values merge_w21 merge21_lbl
label variable merge_w21 "2021 merge result"

gen byte observed_w21 = inlist(merge_w21, 2, 3)

* Cases present only in 2021 entered after the first merge.
replace observed_w23 = 0 if missing(observed_w23)
replace observed_w25 = 0 if missing(observed_w25)
replace linked_w23_w25 = 0 if missing(linked_w23_w25)

label variable observed_w21 "Observed in 2021"

isid hhid pline

egen long panel_id = group(hhid pline)
label variable panel_id "Individual panel identifier: hhid + pline"
isid panel_id


*--------------------------------------------------------------------*
* 5. PANEL PARTICIPATION AND TRACKING STATUS
*--------------------------------------------------------------------*

gen byte waves_observed = observed_w21 + observed_w23 + observed_w25

gen byte panel_w23_w25 = observed_w23 == 1 & observed_w25 == 1

gen byte tracked_panel_w23_w25 =                         ///
    panel_w23_w25 == 1 & istracking_w25 == 1

gen byte panel_w21_w23_w25 =                             ///
    observed_w21 == 1 & observed_w23 == 1 & observed_w25 == 1

gen byte tracked_panel_w21_w23_w25 =                     ///
    panel_w21_w23_w25 == 1 &                             ///
    istracking_w23 == 1 & istracking_w25 == 1

label variable waves_observed "Number of observed waves, 2021-2025"
label variable panel_w23_w25 "Observed in both 2023 and 2025"
label variable tracked_panel_w23_w25                     ///
    "Tracked respondent observed in 2023 and 2025"
label variable panel_w21_w23_w25                         ///
    "Observed in 2021, 2023, and 2025"
label variable tracked_panel_w21_w23_w25                 ///
    "Tracking panel observed in 2021, 2023, and 2025"

display as text "Tracking status among linked 2023-2025 respondents:"
tabulate istracking_w25 if panel_w23_w25 == 1, missing

display as text "Number of waves observed:"
tabulate waves_observed, missing


*--------------------------------------------------------------------*
* 6. AGE ELIGIBILITY AT THE 2023 BASELINE
*--------------------------------------------------------------------*

gen int age_w23 = 2023 - birthyear_w23
replace age_w23 = . if !inrange(age_w23, 0, 100)

gen byte ageeligible_w23 = inrange(age_w23, 18, 65)      ///
    if !missing(age_w23)

label variable age_w23 "Age in 2023"
label variable ageeligible_w23 "Aged 18-65 in 2023"


*--------------------------------------------------------------------*
* 7. INITIAL GAI AND PAI AVAILABILITY SAMPLES
*--------------------------------------------------------------------*

* These are outcome-availability indicators, not complete-case samples.
* GAI and PAI are deliberately defined independently.

gen byte available_gai =                                 ///
    tracked_panel_w23_w25 == 1 &                         ///
    ageeligible_w23 == 1 &                               ///
    !missing(gai_use_w25)

gen byte available_pai =                                 ///
    tracked_panel_w23_w25 == 1 &                         ///
    ageeligible_w23 == 1 &                               ///
    !missing(pai_use_w25)

label variable available_gai "Available for initial GAI analysis"
label variable available_pai "Available for initial PAI analysis"

display as text "Initial GAI availability sample:"
count if available_gai == 1
tabulate gai_use_w25 if available_gai == 1, missing

display as text "Initial PAI availability sample:"
count if available_pai == 1
tabulate pai_use_w25 if available_pai == 1, missing


*--------------------------------------------------------------------*
* 8. INCOME AVAILABILITY -- HOUSEHOLD AND INDIVIDUAL KEPT SEPARATE
*--------------------------------------------------------------------*

gen byte hh_income_w23_w25 =                             ///
    panel_w23_w25 == 1 &                                 ///
    !missing(hh_income_w23, hh_income_w25)

gen byte hh_income_w21_w23_w25 =                         ///
    panel_w21_w23_w25 == 1 &                             ///
    !missing(hh_income_w21, hh_income_w23, hh_income_w25)

gen byte ind_income_w23_w25 =                            ///
    panel_w23_w25 == 1 &                                 ///
    !missing(ind_income_w23, ind_income_w25)

gen byte ind_income_w21_w23_w25 =                        ///
    panel_w21_w23_w25 == 1 &                             ///
    !missing(ind_income_w21, ind_income_w23, ind_income_w25)

label variable hh_income_w23_w25                         ///
    "Household income observed in 2023 and 2025"
label variable hh_income_w21_w23_w25                     ///
    "Household income observed in all three waves"
label variable ind_income_w23_w25                        ///
    "Individual reported income observed in 2023 and 2025"
label variable ind_income_w21_w23_w25                    ///
    "Individual reported income observed in all three waves"

* Combined availability flags for later use; no observations are dropped.
gen byte available_gai_hhinc_w23_w25 =                   ///
    available_gai == 1 & hh_income_w23_w25 == 1

gen byte available_gai_indinc_w23_w25 =                  ///
    available_gai == 1 & ind_income_w23_w25 == 1

gen byte available_pai_hhinc_w23_w25 =                   ///
    available_pai == 1 & hh_income_w23_w25 == 1

gen byte available_pai_indinc_w23_w25 =                  ///
    available_pai == 1 & ind_income_w23_w25 == 1


*--------------------------------------------------------------------*
* 9. EMPLOYMENT TRANSITIONS: RETAIN AS MECHANISMS, NOT CORE CONTROLS
*--------------------------------------------------------------------*

* A direct job-change question would be preferable. These variables are
* transparent proxies based on changes in recorded employment status,
* industry, and occupation. They are not used to define the main sample.

capture confirm variable havejob_w23
local havejob23_exists = (_rc == 0)

capture confirm variable havejob_w25
local havejob25_exists = (_rc == 0)

local havejob_binary 0

if `havejob23_exists' == 1 & `havejob25_exists' == 1 {
    capture assert inlist(havejob_w23, 0, 1, .) &         ///
        inlist(havejob_w25, 0, 1, .)

    if !_rc {
        local havejob_binary 1

        gen byte employment_change_w23_w25 =              ///
            havejob_w23 != havejob_w25                    ///
            if !missing(havejob_w23, havejob_w25)

        label variable employment_change_w23_w25          ///
            "Employment status changed between 2023 and 2025"
    }
    else {
        display as text                                   ///
            "havejob is not coded 0/1 in both waves; no employment-change indicator created."
    }
}

capture confirm variable industry_w23
local industry23_exists = (_rc == 0)

capture confirm variable industry_w25
local industry25_exists = (_rc == 0)

if `industry23_exists' == 1 & `industry25_exists' == 1 &  ///
   `havejob_binary' == 1 {
    gen byte industry_change_w23_w25 =                    ///
        industry_w23 != industry_w25                      ///
        if havejob_w23 == 1 & havejob_w25 == 1 &          ///
        !missing(industry_w23, industry_w25)

    label variable industry_change_w23_w25                ///
        "Industry changed among workers between 2023 and 2025"
}

capture confirm variable occupation_w23
local occupation23_exists = (_rc == 0)

capture confirm variable occupation_w25
local occupation25_exists = (_rc == 0)

if `occupation23_exists' == 1 & `occupation25_exists' == 1 & ///
   `havejob_binary' == 1 {
    gen byte occupation_change_w23_w25 =                  ///
        occupation_w23 != occupation_w25                  ///
        if havejob_w23 == 1 & havejob_w25 == 1 &          ///
        !missing(occupation_w23, occupation_w25)

    label variable occupation_change_w23_w25              ///
        "Occupation changed among workers between 2023 and 2025"
}

* Additional-job transitions are constructed only when both waves use
* the verified 0=no, 1=yes coding from the income-construction files.
capture confirm variable other_job_w23
local otherjob23_exists = (_rc == 0)

capture confirm variable other_job_w25
local otherjob25_exists = (_rc == 0)

if `otherjob23_exists' == 1 & `otherjob25_exists' == 1 {
    capture assert inlist(other_job_w23, 0, 1, .) &        ///
        inlist(other_job_w25, 0, 1, .)

    if !_rc {
        gen byte started_other_job_w23_w25 =               ///
            other_job_w23 == 0 & other_job_w25 == 1       ///
            if !missing(other_job_w23, other_job_w25)

        gen byte stopped_other_job_w23_w25 =               ///
            other_job_w23 == 1 & other_job_w25 == 0       ///
            if !missing(other_job_w23, other_job_w25)

        label variable started_other_job_w23_w25           ///
            "Started an additional job between 2023 and 2025"
        label variable stopped_other_job_w23_w25           ///
            "Stopped an additional job between 2023 and 2025"
    }
}


*--------------------------------------------------------------------*
* 10. DIGITAL-DEVICE ACCESS: CONSTRUCT ONLY IF BINARY CODING IS 0/1
*--------------------------------------------------------------------*

capture label define device_profile_lbl                  ///
    0 "Neither phone nor computer"                      ///
    1 "Phone only"                                      ///
    2 "Computer only"                                   ///
    3 "Phone and computer"

foreach y in 21 23 {
    capture confirm variable have_phone_w`y'
    local phone_exists = (_rc == 0)

    capture confirm variable have_computer_w`y'
    local computer_exists = (_rc == 0)

    if `phone_exists' == 1 & `computer_exists' == 1 {
        capture assert inlist(have_phone_w`y', 0, 1, .) & ///
            inlist(have_computer_w`y', 0, 1, .)

        if !_rc {
            gen byte device_count_w`y' =                 ///
                have_phone_w`y' + have_computer_w`y'     ///
                if !missing(have_phone_w`y', have_computer_w`y')

            gen byte device_profile_w`y' = .
            replace device_profile_w`y' = 0 if           ///
                have_phone_w`y' == 0 & have_computer_w`y' == 0
            replace device_profile_w`y' = 1 if           ///
                have_phone_w`y' == 1 & have_computer_w`y' == 0
            replace device_profile_w`y' = 2 if           ///
                have_phone_w`y' == 0 & have_computer_w`y' == 1
            replace device_profile_w`y' = 3 if           ///
                have_phone_w`y' == 1 & have_computer_w`y' == 1

            label values device_profile_w`y' device_profile_lbl
            label variable device_count_w`y'             ///
                "Number of device types available"
            label variable device_profile_w`y'           ///
                "Phone and computer access profile"
        }
        else {
            display as text                              ///
                "Device ownership in wave 20`y' is not coded 0/1."
            display as text                              ///
                "Raw variables retained; inspect them before recoding."
        }
    }
}


*--------------------------------------------------------------------*
* 11. DIAGNOSTICS BEFORE ANY COMPLETE-CASE SAMPLE IS DEFINED
*--------------------------------------------------------------------*

display as text "2023 AI-variable coding and questionnaire routing:"
tabulate ai_awareness_w23, missing
tabulate ai_familiarity_w23, missing
tabulate ai_use_w23, missing
tabulate ai_awareness_w23 ai_familiarity_w23, missing
tabulate ai_awareness_w23 ai_use_w23, missing

display as text "Availability of 2023 AI predictors in the GAI sample:"
count if available_gai == 1
count if available_gai == 1 & !missing(ai_awareness_w23)
count if available_gai == 1 & !missing(ai_familiarity_w23)
count if available_gai == 1 & !missing(ai_use_w23)

display as text "Household-income availability:"
count if hh_income_w23_w25 == 1
count if hh_income_w21_w23_w25 == 1

display as text "Individual-income availability:"
count if ind_income_w23_w25 == 1
count if ind_income_w21_w23_w25 == 1

* Device coding/value diagnostics. These commands are captured because
* a device variable may legitimately be absent from one delivered wave.
capture noisily tabulate have_phone_w21, missing
capture noisily tabulate have_computer_w21, missing
capture noisily summarize phone_value_w21 computer_value_w21, detail

capture noisily tabulate have_phone_w23, missing
capture noisily tabulate have_computer_w23, missing
capture noisily summarize phone_value_w23 computer_value_w23, detail

* Weight diagnostics. Household and individual weights remain separate.
capture noisily summarize household_weight_w21 individual_weight_w21
capture noisily summarize household_weight_w23 individual_weight_w23
capture noisily summarize household_weight_w25 individual_weight_w25


*--------------------------------------------------------------------*
* 12. ORDER AND SAVE THE PERSON-LEVEL WIDE FILE
*--------------------------------------------------------------------*

order panel_id hhid pline                               ///
      observed_w21 observed_w23 observed_w25             ///
      waves_observed panel_w23_w25 tracked_panel_w23_w25 ///
      panel_w21_w23_w25 tracked_panel_w21_w23_w25, first

sort hhid pline
compress
isid hhid pline
isid panel_id

save "`widefile'", replace

display as result "Final wide preparation file saved to:"
display as result "`widefile'"
display as result "Merge identifier: hhid + pline"
display as text   "No complete-case regression sample was imposed."
