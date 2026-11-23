version 16.0
set more off

/*
    SELECTION, MISSING-DATA, AND ATTRITION ROBUSTNESS CHECKS

    Run this file after:
      12_final_ordered_incorporation_tables.do
      13_longitudinal_economic_returns.do

    Run 14_table5_institutional_field_ai_outcomes.do first if Table 5
    variables should also appear in the missingness and sample-flow workbook.

    The file does not load, merge, append, reshape, save, or overwrite the
    wide analysis data. It does not identify one AI respondent per household
    and does not test household-level uniqueness.

    Outputs:
      1. Missingness and analytical sample flow
      2. Baseline comparison of retained and excluded respondents
      3. Stabilized inverse-probability-of-observation robustness models

    The inverse-probability models adjust only for observed 2023
    characteristics. They do not establish causal identification or remove
    selection on unobserved characteristics.
*/


*--------------------------------------------------------------------*
* 0. OUTPUT, LOG, PREREQUISITES, AND CLEANUP
*--------------------------------------------------------------------*

if `"$project_root"' == "" global project_root "."

global rob_results "$project_root/results/robustness"
global rob_tables  "$rob_results/tables"
global rob_logs    "$rob_results/logs"

capture mkdir "$project_root/results"
capture mkdir "$rob_results"
capture mkdir "$rob_tables"
capture mkdir "$rob_logs"

capture log close _all
log using "$rob_logs/15_selection_missingness_ipw_robustness.log", ///
    text replace

* Drop only variables created by an earlier run of this do file.
capture drop rob_*

capture which esttab
if _rc {
    display as error "The estout package is required. Install it once with:"
    display as error "ssc install estout"
    log close
    exit 199
}

local required                                            ///
    t8_age t8_gai_breadth t8_gai_time4                  ///
    t8_pai_breadth t8_pai_time4                         ///
    t8_s_gb_link t8_s_gt_link t8_s_pb_link t8_s_pt_link ///
    t8_linked_complete t8_weight t8_city_cluster        ///
    t13_age23 t13_age25 t13_female23 t13_education23   ///
    t13_marriage23 t13_job23 t13_hukoulive23           ///
    t13_city_tier23 t13_region23 t13_ccp23             ///
    t13_ihs_eqinc22 t13_phone23 t13_computer23         ///
    t13_ihs_phonevalue23 t13_ihs_computervalue23       ///
    t13_awareness23 t13_familiarity_z23 t13_aiuse23    ///
    t13_job25 t13_ihs_indinc22 t13_ihs_indinc24        ///
    t13_ihs_eqinc24 t13_hours22_1000 t13_hours24_1000 ///
    t13_sample_ind t13_sample_hh t13_sample_hours      ///
    t13_ai_weight t13_hh_weight t13_city_cluster

foreach v of local required {
    capture confirm variable `v'
    if _rc {
        display as error "Required analysis variable `v' was not found."
        display as error "Run do files 12 and 13 before this robustness file."
        log close
        exit 111
    }
}


*--------------------------------------------------------------------*
* 1. DEFINE THE BASELINE COHORT AND OBSERVATION INDICATOR
*--------------------------------------------------------------------*

* Ages 16-63 in 2023 define a stable cohort that remains no older than 65
* in 2025. The broader cohort is used to document baseline item nonresponse.
gen byte rob_agecohort23 = inrange(t13_age23, 16, 63)

* Valid baseline AI cognition and use are then required because these are
* focal predictors, not variables to be imputed.
gen byte rob_base23 = rob_agecohort23 == 1 &             ///
    !missing(t13_awareness23, t13_familiarity_z23,      ///
             t13_aiuse23)

* The working-outcome risk set begins with respondents working in 2023.
* The final income and hour samples remain conditional on continuous work.
gen byte rob_base23_work = rob_base23 == 1 & t13_job23 == 1

* Overall retention indicator used only for the baseline balance table.
* Outcome-specific indicators are used for the IPW models below.
gen byte rob_retained25 = rob_base23 == 1 &             ///
    (t8_s_gb_link == 1 | t8_s_gt_link == 1 |           ///
     t8_s_pb_link == 1 | t8_s_pt_link == 1)

label variable rob_base23                               ///
    "Eligible 2023 AI baseline cohort, age 16-63"
label variable rob_retained25                           ///
    "Retained in at least one linked 2025 AI model"

* Cross-sectional eligibility is outcome-specific. Cases outside the AI
* module or routed away from a question are not counted as missing cases.
foreach s in gb gt pb pt {
    local outcome ""
    if "`s'" == "gb" local outcome t8_gai_breadth
    if "`s'" == "gt" local outcome t8_gai_time4
    if "`s'" == "pb" local outcome t8_pai_breadth
    if "`s'" == "pt" local outcome t8_pai_time4

    gen byte rob_t2_eligible_`s' =                     ///
        !missing(t8_age, `outcome')
    gen byte rob_t3_eligible_`s' = rob_base23 == 1 &   ///
        !missing(t8_age, `outcome')
}

egen byte rob_t2_any_eligible = rowmax(                ///
    rob_t2_eligible_gb rob_t2_eligible_gt              ///
    rob_t2_eligible_pb rob_t2_eligible_pt)
egen byte rob_t3_any_eligible = rowmax(                ///
    rob_t3_eligible_gb rob_t3_eligible_gt              ///
    rob_t3_eligible_pb rob_t3_eligible_pt)

* Table 4 has three different analysis universes. Household income does
* not require continuous employment; individual income and work hours do.
gen byte rob_t4_eligible_ind = rob_base23 == 1 &        ///
    !missing(t13_age25) & t13_job23 == 1 &             ///
    t13_job25 == 1 &                                   ///
    !missing(t13_ihs_indinc22, t13_ihs_indinc24)

gen byte rob_t4_eligible_hh = rob_base23 == 1 &         ///
    !missing(t13_age25, t13_ihs_eqinc22, t13_ihs_eqinc24)

gen byte rob_t4_eligible_hours = rob_base23 == 1 &      ///
    !missing(t13_age25) & t13_job23 == 1 &             ///
    t13_job25 == 1 &                                   ///
    !missing(t13_hours22_1000, t13_hours24_1000)

egen byte rob_t4_any_eligible = rowmax(                ///
    rob_t4_eligible_ind rob_t4_eligible_hh             ///
    rob_t4_eligible_hours)

* Table 5 eligibility is also outcome-specific. Impact outcomes are
* automatically conditional on corresponding users because the constructed
* variables are missing for nonusers.
capture confirm variable t15_age
if !_rc {
    foreach outcome in gai_use gai_breadth gai_time gai_aug gai_pressure ///
                       pai_use pai_breadth pai_time pai_aug pai_pressure {
        gen byte rob_t5_eligible_`outcome' =            ///
            !missing(t15_age, t15_`outcome')
    }
    egen byte rob_t5_any_eligible = rowmax(             ///
        rob_t5_eligible_gai_use                         ///
        rob_t5_eligible_gai_breadth                     ///
        rob_t5_eligible_gai_time                        ///
        rob_t5_eligible_gai_aug                         ///
        rob_t5_eligible_gai_pressure                    ///
        rob_t5_eligible_pai_use                         ///
        rob_t5_eligible_pai_breadth                     ///
        rob_t5_eligible_pai_time                        ///
        rob_t5_eligible_pai_aug                         ///
        rob_t5_eligible_pai_pressure)
}

quietly count if rob_base23 == 1
local rob_n_base = r(N)
quietly count if rob_agecohort23 == 1
local rob_n_agecohort = r(N)
quietly count if rob_retained25 == 1
local rob_n_retained = r(N)

if `rob_n_base' == 0 | `rob_n_retained' == 0 {
    display as error "The baseline or retained sample is empty."
    log close
    exit 2000
}

display as result "Eligible 2023 baseline cohort: `rob_n_base'"
display as result "Retained for linked AI analysis: `rob_n_retained'"


*--------------------------------------------------------------------*
* 2. MISSINGNESS TABLE
*--------------------------------------------------------------------*

tempfile rob_missing
tempname rob_post_missing

postfile `rob_post_missing'                              ///
    str24 analysis str40 variable str100 variable_label ///
    double eligible_n missing_n missing_percent         ///
    using `rob_missing', replace

* Table 2: 2025 cross-sectional AI incorporation.
local rob_t2_vars                                        ///
    t8_gai_breadth t8_gai_time4                         ///
    t8_pai_breadth t8_pai_time4                        ///
    t8_female t8_education t8_ihs_eqincome             ///
    t8_empstudent t8_hukoulive t8_city_tier t8_region  ///
    t8_ccp_member t8_marriage                          ///
    t8_income_expect t8_job_expect t8_weight

quietly count if rob_t2_any_eligible == 1
local rob_t2_denom = r(N)

foreach v of local rob_t2_vars {
    local vl : variable label `v'
    if `"`vl'"' == "" local vl "`v'"
    quietly count if rob_t2_any_eligible == 1 & missing(`v')
    local nm = r(N)
    local pm = 100*`nm'/`rob_t2_denom'
    post `rob_post_missing'                             ///
        ("Table 2, 2025") ("`v'") (`"`vl'"')          ///
        (`rob_t2_denom') (`nm') (`pm')
}

* Table 3: linked cognition, devices, and 2025 incorporation.
local rob_t3_vars                                        ///
    t8_gai_breadth t8_gai_time4                        ///
    t8_pai_breadth t8_pai_time4                        ///
    t8_age23 t8_female23 t8_education23               ///
    t8_ihs_eqincome23 t8_hasjob23 t8_hukoulive23      ///
    t8_city_tier23 t8_region23 t8_ccp_member23         ///
    t8_marriage23 t8_phone t8_computer                 ///
    t8_ihs_phone_value t8_ihs_computer_value           ///
    t8_ai_awareness23 t8_ai_familiarity_z              ///
    t8_prior_ai_use t8_weight

foreach v of local rob_t3_vars {
    local vl : variable label `v'
    if `"`vl'"' == "" local vl "`v'"
    quietly count if rob_t3_any_eligible == 1 & missing(`v')
    local nm = r(N)
    quietly count if rob_t3_any_eligible == 1
    local rob_t3_denom = r(N)
    local pm = 100*`nm'/`rob_t3_denom'
    post `rob_post_missing'                             ///
        ("Table 3, linked") ("`v'") (`"`vl'"')        ///
        (`rob_t3_denom') (`nm') (`pm')
}

* Table 4: prospective economic outcomes.
local rob_t4_vars                                        ///
    t13_ihs_indinc22 t13_ihs_indinc24                  ///
    t13_ihs_eqinc22 t13_ihs_eqinc24                    ///
    t13_hours22_1000 t13_hours24_1000                  ///
    t13_female23 t13_education23 t13_marriage23       ///
    t13_job23 t13_job25 t13_hukoulive23               ///
    t13_city_tier23 t13_region23 t13_ccp23             ///
    t13_industry23 t13_phone23 t13_computer23          ///
    t13_ihs_phonevalue23 t13_ihs_computervalue23       ///
    t13_awareness23 t13_familiarity_z23 t13_aiuse23    ///
    t13_ai_weight t13_hh_weight

foreach v of local rob_t4_vars {
    local vl : variable label `v'
    if `"`vl'"' == "" local vl "`v'"
    quietly count if rob_t4_any_eligible == 1 & missing(`v')
    local nm = r(N)
    quietly count if rob_t4_any_eligible == 1
    local rob_t4_denom = r(N)
    local pm = 100*`nm'/`rob_t4_denom'
    post `rob_post_missing'                             ///
        ("Table 4, linked") ("`v'") (`"`vl'"')        ///
        (`rob_t4_denom') (`nm') (`pm')
}

* Table 5 is included when do file 14 has already been run.
capture confirm variable t15_age
if !_rc {
    local rob_t5_vars                                    ///
        t15_gai_breadth t15_gai_time                   ///
        t15_pai_use t15_pai_breadth t15_pai_time      ///
        t15_gai_aug t15_gai_pressure                   ///
        t15_pai_aug t15_pai_pressure                   ///
        t15_female t15_education t15_ihs_eqincome     ///
        t15_marriage t15_hukoulive t15_city_tier      ///
        t15_region t15_ccp t15_empstudent             ///
        t15_industry_detail t15_policy_intensity      ///
        t15_weight

    quietly count if rob_t5_any_eligible == 1
    local rob_t5_denom = r(N)

    foreach v of local rob_t5_vars {
        capture confirm variable `v'
        if !_rc {
            local vl : variable label `v'
            if `"`vl'"' == "" local vl "`v'"
            quietly count if rob_t5_any_eligible == 1 & missing(`v')
            local nm = r(N)
            local pm = 100*`nm'/`rob_t5_denom'
            post `rob_post_missing'                     ///
                ("Table 5, 2025") ("`v'") (`"`vl'"')  ///
                (`rob_t5_denom') (`nm') (`pm')
        }
    }
}

postclose `rob_post_missing'


*--------------------------------------------------------------------*
* 3. ANALYTICAL SAMPLE FLOW
*--------------------------------------------------------------------*

tempfile rob_flow
tempname rob_post_flow

postfile `rob_post_flow'                                ///
    str24 analysis str70 sample_stage                   ///
    double baseline_n preceding_stage_n retained_n     ///
    percent_of_preceding percent_of_baseline           ///
    using `rob_flow', replace

* Table 2 is cross-sectional. Each outcome begins with the respondents who
* were age eligible and had a valid response to that particular AI outcome.
foreach s in gb gt pb pt {
    local label ""
    if "`s'" == "gb" local label "Generative AI breadth"
    if "`s'" == "gt" local label "Generative AI time"
    if "`s'" == "pb" local label "Specialised AI breadth"
    if "`s'" == "pt" local label "Specialised AI time"

    quietly count if rob_t2_eligible_`s' == 1
    local base = r(N)
    post `rob_post_flow' ("Table 2")                  ///
        ("Eligible 2025 `label' respondents")         ///
        (`base') (`base') (`base') (100) (100)

    quietly count if rob_t2_eligible_`s' == 1 &        ///
        t8_s_`s'_m2 == 1
    local n = r(N)
    post `rob_post_flow' ("Table 2")                  ///
        ("Final `label' complete-case sample")        ///
        (`base') (`base') (`n')                        ///
        (100*`n'/`base') (100*`n'/`base')
}

* Table 3 separates genuine panel linkage from complete-case loss. The
* baseline is the valid 2023 AI cohort; the preceding denominator for each
* final model is the linked, outcome-eligible sample.
post `rob_post_flow' ("Table 3")                       ///
    ("Valid 2023 AI baseline cohort, age 16-63")       ///
    (`rob_n_base') (`rob_n_base') (`rob_n_base') (100) (100)

foreach s in gb gt pb pt {
    local label ""
    if "`s'" == "gb" local label "Generative AI breadth"
    if "`s'" == "gt" local label "Generative AI time"
    if "`s'" == "pb" local label "Specialised AI breadth"
    if "`s'" == "pt" local label "Specialised AI time"

    quietly count if rob_t3_eligible_`s' == 1
    local linked = r(N)
    post `rob_post_flow' ("Table 3")                  ///
        ("Linked with valid 2025 `label'")            ///
        (`rob_n_base') (`rob_n_base') (`linked')       ///
        (100*`linked'/`rob_n_base')                    ///
        (100*`linked'/`rob_n_base')

    quietly count if rob_t3_eligible_`s' == 1 &        ///
        t8_s_`s'_link == 1
    local n = r(N)
    post `rob_post_flow' ("Table 3")                  ///
        ("Final `label' complete-case sample")        ///
        (`rob_n_base') (`linked') (`n')                ///
        (100*`n'/`linked') (100*`n'/`rob_n_base')
}

* Table 4 uses separate eligibility bases for individual income,
* household income, and working hours.
post `rob_post_flow' ("Table 4")                       ///
    ("Valid 2023 AI baseline cohort, age 16-63")       ///
    (`rob_n_base') (`rob_n_base') (`rob_n_base') (100) (100)

foreach s in ind hh hours {
    local label ""
    if "`s'" == "ind" local label "individual income"
    if "`s'" == "hh" local label "household income"
    if "`s'" == "hours" local label "working hours"

    quietly count if rob_t4_eligible_`s' == 1
    local eligible = r(N)
    post `rob_post_flow' ("Table 4")                  ///
        ("Linked and outcome-eligible: `label'")      ///
        (`rob_n_base') (`rob_n_base') (`eligible')     ///
        (100*`eligible'/`rob_n_base')                  ///
        (100*`eligible'/`rob_n_base')

    quietly count if rob_t4_eligible_`s' == 1 &        ///
        t13_sample_`s' == 1
    local n = r(N)
    post `rob_post_flow' ("Table 4")                  ///
        ("Final `label' complete-case sample")        ///
        (`rob_n_base') (`eligible') (`n')              ///
        (100*`n'/`eligible') (100*`n'/`rob_n_base')
}

* Table 5 is cross-sectional and outcome-specific. Consequence outcomes
* use corresponding AI users as their questionnaire universe.
capture confirm variable t15_age
if !_rc {
    foreach s in gai_use gai_breadth gai_time gai_aug gai_pressure ///
                     pai_use pai_breadth pai_time pai_aug pai_pressure {
        capture confirm variable t15_sample_`s'
        if !_rc {
            quietly count if rob_t5_eligible_`s' == 1
            local base = r(N)
            post `rob_post_flow' ("Table 5")          ///
                ("Eligible 2025 `s' respondents")     ///
                (`base') (`base') (`base') (100) (100)

            quietly count if rob_t5_eligible_`s' == 1 & ///
                t15_sample_`s' == 1
            local n = r(N)
            post `rob_post_flow' ("Table 5")          ///
                ("Final `s' complete-case sample")    ///
                (`base') (`base') (`n')                ///
                (100*`n'/`base') (100*`n'/`base')
        }
    }
}

postclose `rob_post_flow'


*--------------------------------------------------------------------*
* 4. RETAINED-VERSUS-EXCLUDED BASELINE BALANCE
*--------------------------------------------------------------------*

tempfile rob_balance
tempname rob_post_balance

postfile `rob_post_balance'                             ///
    str40 variable str24 category                      ///
    double retained_valid excluded_valid               ///
    double retained_mean excluded_mean standardized_difference ///
    using `rob_balance', replace

* Continuous and binary variables. For binary variables, the means are
* proportions and the same pooled-standard-deviation formula applies.
local rob_balance_simple                                ///
    t13_age23 t13_female23 t13_ihs_eqinc22             ///
    t13_job23 t13_ccp23 t13_phone23 t13_computer23     ///
    t13_ihs_phonevalue23 t13_ihs_computervalue23       ///
    t13_awareness23 t13_familiarity_z23 t13_aiuse23

foreach v of local rob_balance_simple {
    quietly summarize `v' if rob_base23 == 1 & rob_retained25 == 1
    local n1 = r(N)
    local m1 = r(mean)
    local s1 = r(sd)

    quietly summarize `v' if rob_base23 == 1 & rob_retained25 == 0
    local n0 = r(N)
    local m0 = r(mean)
    local s0 = r(sd)

    local smd = .
    local psd = sqrt((`s1'^2 + `s0'^2)/2)
    if !missing(`psd') & `psd' > 0 { 
        local smd = (`m1'-`m0')/`psd'
    }

    local vl : variable label `v'
    if `"`vl'"' == "" local vl "`v'"
    post `rob_post_balance' (`"`vl'"') ("Overall")    ///
        (`n1') (`n0') (`m1') (`m0') (`smd')
}

* For categorical variables, report a standardized difference for each
* category as a binary proportion. The category values are retained so the
* workbook can be read with the value labels in the main codebook.
local rob_balance_cat                                   ///
    t13_education23 t13_marriage23 t13_hukoulive23     ///
    t13_city_tier23 t13_region23

foreach v of local rob_balance_cat {
    quietly levelsof `v' if rob_base23 == 1 & !missing(`v'), ///
        local(rob_levels)
    local vl : variable label `v'
    if `"`vl'"' == "" local vl "`v'"

    foreach lev of local rob_levels {
        quietly count if rob_base23 == 1 &              ///
            rob_retained25 == 1 & !missing(`v')
        local n1 = r(N)
        quietly count if rob_base23 == 1 &              ///
            rob_retained25 == 1 & `v' == `lev'
        local c1 = r(N)
        local p1 = `c1'/`n1'

        quietly count if rob_base23 == 1 &              ///
            rob_retained25 == 0 & !missing(`v')
        local n0 = r(N)
        quietly count if rob_base23 == 1 &              ///
            rob_retained25 == 0 & `v' == `lev'
        local c0 = r(N)
        local p0 = `c0'/`n0'

        local smd = .
        local psd = sqrt((`p1'*(1-`p1') +             ///
                          `p0'*(1-`p0'))/2)
        if !missing(`psd') & `psd' > 0 {
            local smd = (`p1'-`p0')/`psd'
        }

        post `rob_post_balance' (`"`vl'"') ("Category `lev'") ///
            (`n1') (`n0') (`p1') (`p0') (`smd')
    }
}

postclose `rob_post_balance'


*--------------------------------------------------------------------*
* 5. EXPORT MISSINGNESS, SAMPLE FLOW, AND BALANCE TO ONE WORKBOOK
*--------------------------------------------------------------------*

preserve
use `rob_missing', clear
sort analysis variable
format missing_percent %9.2f
export excel using "$rob_tables/Selection_missingness_diagnostics.xlsx", ///
    sheet("Missingness") firstrow(variables) replace
restore

preserve
use `rob_flow', clear
sort analysis
format percent_of_preceding percent_of_baseline %9.2f
export excel using "$rob_tables/Selection_missingness_diagnostics.xlsx", ///
    sheet("Sample_flow", replace) firstrow(variables)
restore

preserve
use `rob_balance', clear
gen double abs_standardized_difference =               ///
    abs(standardized_difference)
format retained_mean excluded_mean                     ///
       standardized_difference                         ///
       abs_standardized_difference %9.3f
gsort -abs_standardized_difference
export excel using "$rob_tables/Selection_missingness_diagnostics.xlsx", ///
    sheet("Baseline_balance", replace) firstrow(variables)
restore


*--------------------------------------------------------------------*
* 6. PREPARE COMPLETE PREDICTORS FOR THE SELECTION MODELS
*--------------------------------------------------------------------*

gen double rob_age23 = t13_age23 if rob_base23 == 1
gen double rob_age23_sq = rob_age23^2 if rob_base23 == 1

* Median replacement here is used only inside the response-propensity
* model. A missingness indicator preserves information about nonresponse.
quietly summarize t13_ihs_eqinc22 if rob_base23 == 1, detail
local rob_med_eqinc = r(p50)
if missing(`rob_med_eqinc') local rob_med_eqinc = 0
gen double rob_eqinc22 = t13_ihs_eqinc22 if rob_base23 == 1
gen byte rob_eqinc22_miss = missing(t13_ihs_eqinc22) if rob_base23 == 1
replace rob_eqinc22 = `rob_med_eqinc' if                ///
    rob_base23 == 1 & missing(rob_eqinc22)

quietly summarize t13_ihs_phonevalue23 if rob_base23 == 1, detail
local rob_med_phone = r(p50)
if missing(`rob_med_phone') local rob_med_phone = 0
gen double rob_phonevalue23 = t13_ihs_phonevalue23 if rob_base23 == 1
gen byte rob_phonevalue23_miss =                        ///
    missing(t13_ihs_phonevalue23) if rob_base23 == 1
replace rob_phonevalue23 = `rob_med_phone' if           ///
    rob_base23 == 1 & missing(rob_phonevalue23)

quietly summarize t13_ihs_computervalue23 if rob_base23 == 1, detail
local rob_med_computer = r(p50)
if missing(`rob_med_computer') local rob_med_computer = 0
gen double rob_computervalue23 =                        ///
    t13_ihs_computervalue23 if rob_base23 == 1
gen byte rob_computervalue23_miss =                     ///
    missing(t13_ihs_computervalue23) if rob_base23 == 1
replace rob_computervalue23 = `rob_med_computer' if     ///
    rob_base23 == 1 & missing(rob_computervalue23)

* Missing categories are coded 99 only inside the selection model. They are
* not recoded to substantive categories in any outcome model.
foreach pair in                                          ///
    female23 education23 marriage23 job23 hukoulive23   ///
    citytier23 region23 ccp23 phone23 computer23        ///
    awareness23 aiuse23 {
    local source ""
    if "`pair'" == "female23"    local source t13_female23
    if "`pair'" == "education23" local source t13_education23
    if "`pair'" == "marriage23"  local source t13_marriage23
    if "`pair'" == "job23"       local source t13_job23
    if "`pair'" == "hukoulive23" local source t13_hukoulive23
    if "`pair'" == "citytier23"  local source t13_city_tier23
    if "`pair'" == "region23"    local source t13_region23
    if "`pair'" == "ccp23"       local source t13_ccp23
    if "`pair'" == "phone23"     local source t13_phone23
    if "`pair'" == "computer23"  local source t13_computer23
    if "`pair'" == "awareness23" local source t13_awareness23
    if "`pair'" == "aiuse23"     local source t13_aiuse23

    gen int rob_s_`pair' = `source' if rob_base23 == 1
    replace rob_s_`pair' = 99 if                       ///
        rob_base23 == 1 & missing(rob_s_`pair')
}

gen double rob_familiarity23 =                         ///
    t13_familiarity_z23 if rob_base23 == 1

local rob_selection_covariates                          ///
    c.rob_age23 c.rob_age23_sq                         ///
    i.rob_s_female23 i.rob_s_education23              ///
    i.rob_s_marriage23 i.rob_s_job23                  ///
    i.rob_s_hukoulive23 i.rob_s_citytier23            ///
    i.rob_s_region23 i.rob_s_ccp23                    ///
    c.rob_eqinc22 i.rob_eqinc22_miss                  ///
    i.rob_s_phone23 i.rob_s_computer23                ///
    c.rob_phonevalue23 c.rob_computervalue23          ///
    i.rob_phonevalue23_miss i.rob_computervalue23_miss ///
    i.rob_s_awareness23 c.rob_familiarity23            ///
    i.rob_s_aiuse23


*--------------------------------------------------------------------*
* 7. CONSTRUCT STABILIZED, TRIMMED OBSERVATION WEIGHTS
*--------------------------------------------------------------------*

tempfile rob_ipw_diag
tempname rob_post_ipw
postfile `rob_post_ipw'                                 ///
    str24 outcome double risk_set_n selected_n          ///
    double selection_rate min_probability max_probability ///
    double ipw_p1 ipw_p99 trimmed_ipw_mean trimmed_ipw_max ///
    using `rob_ipw_diag', replace

local rob_weight_sets "gb gt pb pt ind hh hours"

foreach s of local rob_weight_sets {
    local samplevar ""
    local basevar "rob_base23"
    local surveyweight ""
    local outlabel ""

    if "`s'" == "gb" {
        local samplevar t8_s_gb_link
        local surveyweight t8_weight
        local outlabel "Generative AI breadth"
    }
    if "`s'" == "gt" {
        local samplevar t8_s_gt_link
        local surveyweight t8_weight
        local outlabel "Generative AI time"
    }
    if "`s'" == "pb" {
        local samplevar t8_s_pb_link
        local surveyweight t8_weight
        local outlabel "Specialised AI breadth"
    }
    if "`s'" == "pt" {
        local samplevar t8_s_pt_link
        local surveyweight t8_weight
        local outlabel "Specialised AI time"
    }
    if "`s'" == "ind" {
        local samplevar t13_sample_ind
        local basevar rob_base23_work
        local surveyweight t13_ai_weight
        local outlabel "Individual income"
    }
    if "`s'" == "hh" {
        local samplevar t13_sample_hh
        local surveyweight t13_hh_weight
        local outlabel "Household income"
    }
    if "`s'" == "hours" {
        local samplevar t13_sample_hours
        local basevar rob_base23_work
        local surveyweight t13_ai_weight
        local outlabel "Working time"
    }

    quietly count if `basevar' == 1
    local nrisk = r(N)
    quietly count if `basevar' == 1 & `samplevar' == 1
    local nselected = r(N)

    if `nselected' == 0 | `nselected' == `nrisk' {
        display as error "Selection outcome `s' has no usable variation."
        log close
        exit 2000
    }

    * The response model is intentionally unweighted. The final stabilized
    * observation weight is multiplied by the original analysis weight.
    quietly logit `samplevar' `rob_selection_covariates' ///
        if `basevar' == 1

    predict double rob_pr_`s' if e(sample), pr

    quietly summarize `samplevar' if `basevar' == 1, meanonly
    local pbar = r(mean)

    quietly summarize rob_pr_`s' if                     ///
        `basevar' == 1 & `samplevar' == 1, detail
    local pmin = r(min)
    local pmax = r(max)

    gen double rob_ipw_`s' = `pbar'/rob_pr_`s'          ///
        if `samplevar' == 1 & rob_pr_`s' > 0 &          ///
           !missing(rob_pr_`s')

    quietly summarize rob_ipw_`s' if `samplevar' == 1, detail
    local p1 = r(p1)
    local p99 = r(p99)

    replace rob_ipw_`s' = `p1' if                       ///
        `samplevar' == 1 & rob_ipw_`s' < `p1'
    replace rob_ipw_`s' = `p99' if                      ///
        `samplevar' == 1 & rob_ipw_`s' > `p99'

    gen double rob_weight_`s' =                         ///
        rob_ipw_`s' * `surveyweight' if `samplevar' == 1
    replace rob_weight_`s' = . if rob_weight_`s' <= 0

    quietly summarize rob_ipw_`s' if `samplevar' == 1, detail
    local ipwmean = r(mean)
    local ipwmax = r(max)

    post `rob_post_ipw' (`"`outlabel'"')                ///
        (`nrisk') (`nselected') (`pbar') (`pmin') (`pmax') ///
        (`p1') (`p99') (`ipwmean') (`ipwmax')
}

postclose `rob_post_ipw'

preserve
use `rob_ipw_diag', clear
format selection_rate min_probability max_probability  ///
       ipw_p1 ipw_p99 trimmed_ipw_mean trimmed_ipw_max %9.3f
export excel using "$rob_tables/Selection_missingness_diagnostics.xlsx", ///
    sheet("IPW_diagnostics", replace) firstrow(variables)
restore


*--------------------------------------------------------------------*
* 8. TABLE 3: ORIGINAL VERSUS IPW FINAL LINKED MODELS
*--------------------------------------------------------------------*

local rob_t3_structural                                  ///
    c.t8_age23 c.t8_age23_sq i.t8_female23             ///
    ib1.t8_education23 c.t8_ihs_eqincome23             ///
    i.t8_hasjob23 i.t8_hukoulive23                     ///
    ib1.t8_city_tier23 ib1.t8_region23                 ///
    i.t8_ccp_member23 i.t8_marriage23

local rob_t3_devices                                     ///
    i.t8_phone i.t8_computer                           ///
    c.t8_ihs_phone_value c.t8_ihs_computer_value       ///
    i.t8_phone_value_missing i.t8_computer_value_missing

local rob_t3_ai                                          ///
    i.t8_ai_awareness23 c.t8_ai_familiarity_z          ///
    i.t8_prior_ai_use

eststo clear

foreach s in gb gt pb pt {
    local outcome ""
    local samplevar ""
    if "`s'" == "gb" {
        local outcome t8_gai_breadth
        local samplevar t8_s_gb_link
    }
    if "`s'" == "gt" {
        local outcome t8_gai_time4
        local samplevar t8_s_gt_link
    }
    if "`s'" == "pb" {
        local outcome t8_pai_breadth
        local samplevar t8_s_pb_link
    }
    if "`s'" == "pt" {
        local outcome t8_pai_time4
        local samplevar t8_s_pt_link
    }

    quietly ologit `outcome'                            ///
        `rob_t3_structural' `rob_t3_devices' `rob_t3_ai' ///
        if `samplevar' == 1 [pweight=t8_weight],        ///
        vce(cluster t8_city_cluster)
    eststo ROB_T3_`s'_SURVEY

    quietly ologit `outcome'                            ///
        `rob_t3_structural' `rob_t3_devices' `rob_t3_ai' ///
        if `samplevar' == 1 [pweight=rob_weight_`s'],   ///
        vce(cluster t8_city_cluster)
    eststo ROB_T3_`s'_IPW
}

local rob_t3_keep                                        ///
    1.t8_phone 1.t8_computer                           ///
    t8_ihs_phone_value t8_ihs_computer_value           ///
    1.t8_ai_awareness23 t8_ai_familiarity_z            ///
    1.t8_prior_ai_use

local rob_t3_notes                                      ///
    "Entries are odds ratios from ordered logit models; city-clustered standard errors are in parentheses." ///
    "Survey columns use the original analysis weight. IPW columns multiply that weight by a stabilized inverse probability of observation weight estimated from 2023 characteristics and trimmed at the 1st and 99th percentiles." ///
    "All models retain the original outcome-specific complete-case samples. Selection weights address observed selection only."

esttab ROB_T3_gb_SURVEY ROB_T3_gb_IPW                  ///
       ROB_T3_gt_SURVEY ROB_T3_gt_IPW using            ///
    "$rob_tables/Robustness_Table3_Generative_AI_IPW.rtf", ///
    replace eform b(%9.3f) se(%9.3f)                   ///
    star(* 0.05 ** 0.01 *** 0.001) label               ///
    keep(`rob_t3_keep') order(`rob_t3_keep')           ///
    mtitles("Breadth: survey" "Breadth: IPW"          ///
            "Time: survey" "Time: IPW")              ///
    stats(N, labels("Observations") fmt(%9.0fc))       ///
    title("Selection robustness: Generative AI incorporation") ///
    addnotes(`rob_t3_notes')

esttab ROB_T3_pb_SURVEY ROB_T3_pb_IPW                  ///
       ROB_T3_pt_SURVEY ROB_T3_pt_IPW using            ///
    "$rob_tables/Robustness_Table3_Specialised_AI_IPW.rtf", ///
    replace eform b(%9.3f) se(%9.3f)                   ///
    star(* 0.05 ** 0.01 *** 0.001) label               ///
    keep(`rob_t3_keep') order(`rob_t3_keep')           ///
    mtitles("Breadth: survey" "Breadth: IPW"          ///
            "Time: survey" "Time: IPW")              ///
    stats(N, labels("Observations") fmt(%9.0fc))       ///
    title("Selection robustness: Specialised AI incorporation") ///
    addnotes(`rob_t3_notes')


*--------------------------------------------------------------------*
* 9. TABLE 4: ORIGINAL VERSUS IPW FINAL ECONOMIC MODELS
*--------------------------------------------------------------------*

local rob_t4_demo                                        ///
    c.t13_age23 c.t13_age23_sq i.t13_female23          ///
    i.t13_marriage23

local rob_t4_spatial                                     ///
    i.t13_hukoulive23 ib1.t13_city_tier23              ///
    ib1.t13_region23 i.t13_ccp23

local rob_t4_devices                                     ///
    i.t13_phone23 i.t13_computer23                     ///
    c.t13_ihs_phonevalue23 c.t13_ihs_computervalue23   ///
    i.t13_phonevalue_miss i.t13_computervalue_miss

local rob_t4_ai                                          ///
    i.t13_awareness23 c.t13_familiarity_z23            ///
    i.t13_aiuse23

local rob_t4_ind                                         ///
    c.t13_ihs_indinc22 `rob_t4_demo'                   ///
    ib1.t13_education23 c.t13_ihs_eqinc22              ///
    `rob_t4_spatial' i.t13_industry23                  ///
    `rob_t4_devices' `rob_t4_ai'

local rob_t4_hh                                          ///
    c.t13_ihs_eqinc22 `rob_t4_demo'                    ///
    ib1.t13_education23 i.t13_job23                    ///
    `rob_t4_spatial' `rob_t4_devices' `rob_t4_ai'

local rob_t4_hours                                       ///
    c.t13_hours22_1000 `rob_t4_demo'                   ///
    ib1.t13_education23 c.t13_ihs_eqinc22              ///
    `rob_t4_spatial' i.t13_industry23                  ///
    `rob_t4_devices' `rob_t4_ai'

quietly regress t13_ihs_indinc24 `rob_t4_ind'          ///
    if t13_sample_ind == 1 [pweight=t13_ai_weight],     ///
    vce(cluster t13_city_cluster)
eststo ROB_T4_IND_SURVEY

quietly regress t13_ihs_indinc24 `rob_t4_ind'          ///
    if t13_sample_ind == 1 [pweight=rob_weight_ind],    ///
    vce(cluster t13_city_cluster)
eststo ROB_T4_IND_IPW

quietly regress t13_ihs_eqinc24 `rob_t4_hh'            ///
    if t13_sample_hh == 1 [pweight=t13_hh_weight],      ///
    vce(cluster t13_city_cluster)
eststo ROB_T4_HH_SURVEY

quietly regress t13_ihs_eqinc24 `rob_t4_hh'            ///
    if t13_sample_hh == 1 [pweight=rob_weight_hh],      ///
    vce(cluster t13_city_cluster)
eststo ROB_T4_HH_IPW

quietly regress t13_hours24_1000 `rob_t4_hours'        ///
    if t13_sample_hours == 1 [pweight=t13_ai_weight],   ///
    vce(cluster t13_city_cluster)
eststo ROB_T4_HOURS_SURVEY

quietly regress t13_hours24_1000 `rob_t4_hours'        ///
    if t13_sample_hours == 1 [pweight=rob_weight_hours], ///
    vce(cluster t13_city_cluster)
eststo ROB_T4_HOURS_IPW

local rob_t4_keep                                        ///
    1.t13_phone23 t13_ihs_phonevalue23                 ///
    1.t13_computer23 t13_ihs_computervalue23           ///
    1.t13_awareness23 t13_familiarity_z23              ///
    1.t13_aiuse23

local rob_t4_notes                                      ///
    "Entries are unstandardized OLS coefficients; city-clustered standard errors are in parentheses." ///
    "Survey columns use the original analysis weight. IPW columns multiply that weight by a stabilized inverse probability of observation weight estimated from 2023 characteristics and trimmed at the 1st and 99th percentiles." ///
    "Individual income and working time remain conditional on continuous employment. Household income provides the broader comparison. Results remain associational."

esttab ROB_T4_IND_SURVEY ROB_T4_IND_IPW                ///
       ROB_T4_HH_SURVEY ROB_T4_HH_IPW                  ///
       ROB_T4_HOURS_SURVEY ROB_T4_HOURS_IPW using      ///
    "$rob_tables/Robustness_Table4_Economic_Outcomes_IPW.rtf", ///
    replace b(%9.3f) se(%9.3f)                         ///
    star(* 0.05 ** 0.01 *** 0.001) label               ///
    keep(`rob_t4_keep') order(`rob_t4_keep')           ///
    mtitles("Individual: survey" "Individual: IPW"    ///
            "Household: survey" "Household: IPW"     ///
            "Hours: survey" "Hours: IPW")            ///
    stats(N r2, labels("Observations" "R-squared")    ///
          fmt(%9.0fc %9.3f))                           ///
    title("Selection robustness: subsequent economic outcomes") ///
    addnotes(`rob_t4_notes')


*--------------------------------------------------------------------*
* 10. FINAL DIAGNOSTIC SUMMARY
*--------------------------------------------------------------------*

display as text "Review absolute standardized differences in:"
display as result                                      ///
    "$rob_tables/Selection_missingness_diagnostics.xlsx"
display as text "Values above 0.10 merit explicit discussion."
display as text "Review the IPW diagnostics for very small probabilities"
display as text "or extreme weights before interpreting the robustness models."

log close
