version 16.0
set more off

/*
    TABLE 1: COMPACT DESCRIPTIVE STATISTICS

    Run after, without reloading the wide data:

      12_final_ordered_incorporation_tables.do
      13_longitudinal_economic_returns.do
      14_table5_institutional_field_ai_outcomes.do

    The table follows five principles:
      1. Each substantive variable appears once.
      2. The table reports mean, SD, minimum, median, and maximum only.
      3. Observation counts and sample-specific repetitions are omitted.
      4. Statistics use the relevant analysis-eligible population and the
         corresponding survey weight. Available observations are used for
         each variable; there is no global listwise deletion.
      5. Squared terms, missingness indicators, weights, and cluster IDs are
         omitted because they are transformations or design variables.

    Binary-variable means are proportions. Ordered and nominal variables
    retain the numeric coding used in the models. The notes warn that means
    of nominal codes do not have a substantive metric interpretation.
*/


*--------------------------------------------------------------------*
* 0. OUTPUT, LOG, AND CLEANUP
*--------------------------------------------------------------------*

if `"$project_root"' == "" global project_root "."

global t1d_results "$project_root/results/main_tables"
global t1d_tables  "$t1d_results/tables"
global t1d_logs    "$t1d_results/logs"

capture mkdir "$project_root/results"
capture mkdir "$t1d_results"
capture mkdir "$t1d_tables"
capture mkdir "$t1d_logs"

capture log close _all
log using "$t1d_logs/15_table1_descriptive_statistics_tables2_5.log", ///
    text replace

capture drop t1d_*


*--------------------------------------------------------------------*
* 1. PREREQUISITES
*--------------------------------------------------------------------*

local required                                           ///
    t8_weight t8_age t8_female t8_education            ///
    t8_ihs_eqincome t8_empstudent t8_hukoulive          ///
    t8_city_tier t8_region t8_ccp_member t8_marriage    ///
    t8_income_expect t8_job_expect                      ///
    t8_gai_breadth t8_gai_time4                        ///
    t8_pai_breadth t8_pai_time4                        ///
    t8_age23 t8_phone t8_computer                      ///
    t8_ihs_phone_value t8_ihs_computer_value            ///
    t8_ai_awareness23 t8_ai_familiarity_z              ///
    t8_prior_ai_use                                    ///
    t13_ai_weight t13_hh_weight                        ///
    t13_ihs_indinc22 t13_ihs_indinc24                  ///
    t13_ihs_eqinc22                                    ///
    t13_hours22_1000 t13_hours24_1000                  ///
    t13_sample_ind t13_sample_hh t13_sample_hours      ///
    t15_weight t15_age t15_gai_use t15_pai_use         ///
    t15_gai_aug t15_gai_pressure                       ///
    t15_pai_aug t15_pai_pressure                       ///
    t15_industry_detail t15_policy_intensity

foreach v of local required {
    capture confirm variable `v'
    if _rc {
        display as error "Required variable `v' was not found."
        display as error "Run do-files 12, 13, and 14 before Table 1."
        log close
        exit 111
    }
}


*--------------------------------------------------------------------*
* 2. ANALYSIS-ELIGIBLE DESCRIPTIVE POPULATIONS
*--------------------------------------------------------------------*

* Cross-sectional base: age-eligible 2025 records with at least one valid
* incorporation or consequence outcome. Questionnaire routing is therefore
* not treated as item nonresponse.
gen byte t1d_sample_2025 = !missing(t8_age) &           ///
    (!missing(t8_gai_breadth) | !missing(t8_gai_time4) | ///
     !missing(t8_pai_breadth) | !missing(t8_pai_time4) | ///
     !missing(t15_gai_use) | !missing(t15_pai_use) |   ///
     !missing(t15_gai_aug) | !missing(t15_gai_pressure) | ///
     !missing(t15_pai_aug) | !missing(t15_pai_pressure))

* Linked base: valid 2023 AI measures and at least one valid 2025
* incorporation outcome. It is not the full 2023 individual sample.
gen byte t1d_sample_linked = inrange(t8_age23, 16, 63) & ///
    !missing(t8_age) &                                  ///
    !missing(t8_ai_awareness23, t8_ai_familiarity_z,    ///
             t8_prior_ai_use) &                        ///
    (!missing(t8_gai_breadth) | !missing(t8_gai_time4) | ///
     !missing(t8_pai_breadth) | !missing(t8_pai_time4))


*--------------------------------------------------------------------*
* 3. PROGRAM: ONE ROW PER VARIABLE
*--------------------------------------------------------------------*

capture program drop t1d_post_summary
program define t1d_post_summary
    version 16.0
    syntax varname(numeric) [if], HANDLE(name)          ///
        ROW(integer) DESC(string asis) WVAR(varname)

    marksample touse, novarlist

    quietly count if `touse' &                         ///
        !missing(`varlist', `wvar') & `wvar' > 0
    if r(N) == 0 {
        display as error "No valid observations for `varlist'."
        exit 2000
    }

    * Analytic weights reproduce the relative survey weighting for the
    * descriptive moments without invoking Stata's pweight restriction on
    * summarize.
    quietly summarize `varlist' if `touse' &           ///
        !missing(`varlist', `wvar') & `wvar' > 0       ///
        [aweight=`wvar']
    local mean = r(mean)
    local sd = r(sd)

    * The observed range does not depend on positive weight magnitudes.
    quietly summarize `varlist' if `touse' &           ///
        !missing(`varlist', `wvar') & `wvar' > 0, detail
    local minimum = r(min)
    local maximum = r(max)
    local median = r(p50)

    * Use the weighted median when supported. Fall back to the ordinary
    * median only if this Stata installation rejects analytic weights here.
    capture quietly _pctile `varlist' if `touse' &     ///
        !missing(`varlist', `wvar') & `wvar' > 0       ///
        [aweight=`wvar'], percentiles(50)
    if !_rc local median = r(r1)

    post `handle' (`row') (`"`desc'"')                ///
        (`mean') (`sd') (`minimum') (`median') (`maximum')
end


*--------------------------------------------------------------------*
* 4. POST THE COMPACT TABLE
*--------------------------------------------------------------------*

tempfile t1d_table
tempname t1d_post

postfile `t1d_post' int row_order str80 variable_label ///
    double mean standard_deviation minimum median maximum ///
    using `t1d_table', replace

local r = 0

* AI incorporation and perceived consequences in 2025.
local ++r
t1d_post_summary t15_gai_use if t1d_sample_2025 == 1,  ///
    handle(`t1d_post') row(`r')                        ///
    desc("Generative AI use") wvar(t15_weight)
local ++r
t1d_post_summary t8_gai_breadth if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Generative AI breadth") wvar(t8_weight)
local ++r
t1d_post_summary t8_gai_time4 if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Daily Generative AI use time") wvar(t8_weight)
local ++r
t1d_post_summary t15_pai_use if t1d_sample_2025 == 1,  ///
    handle(`t1d_post') row(`r')                        ///
    desc("Specialised AI use") wvar(t15_weight)
local ++r
t1d_post_summary t8_pai_breadth if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Specialised AI breadth") wvar(t8_weight)
local ++r
t1d_post_summary t8_pai_time4 if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Daily Specialised AI use time") wvar(t8_weight)
local ++r
t1d_post_summary t15_gai_aug if t1d_sample_2025 == 1,  ///
    handle(`t1d_post') row(`r')                        ///
    desc("Productive augmentation from Generative AI") ///
    wvar(t15_weight)
local ++r
t1d_post_summary t15_gai_pressure if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Adaptive pressure from Generative AI") wvar(t15_weight)
local ++r
t1d_post_summary t15_pai_aug if t1d_sample_2025 == 1,  ///
    handle(`t1d_post') row(`r')                        ///
    desc("Productive augmentation from Specialised AI") ///
    wvar(t15_weight)
local ++r
t1d_post_summary t15_pai_pressure if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Adaptive pressure from Specialised AI") wvar(t15_weight)

* Current demographic, socioeconomic, geographic, and expectation measures.
local ++r
t1d_post_summary t8_age if t1d_sample_2025 == 1,       ///
    handle(`t1d_post') row(`r') desc("Age") wvar(t8_weight)
local ++r
t1d_post_summary t8_female if t1d_sample_2025 == 1,    ///
    handle(`t1d_post') row(`r') desc("Female") wvar(t8_weight)
local ++r
t1d_post_summary t8_education if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r') desc("Education") wvar(t8_weight)
local ++r
t1d_post_summary t8_ihs_eqincome if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Equivalized household income, 2024, IHS")   ///
    wvar(t8_weight)
local ++r
t1d_post_summary t8_empstudent if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Employment and student position") wvar(t8_weight)
local ++r
t1d_post_summary t8_marriage if t1d_sample_2025 == 1,  ///
    handle(`t1d_post') row(`r') desc("Marital status") ///
    wvar(t8_weight)
local ++r
t1d_post_summary t8_hukoulive if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Hukou and residence position") wvar(t8_weight)
local ++r
t1d_post_summary t8_city_tier if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r') desc("City tier") wvar(t8_weight)
local ++r
t1d_post_summary t8_region if t1d_sample_2025 == 1,    ///
    handle(`t1d_post') row(`r') desc("Region") wvar(t8_weight)
local ++r
t1d_post_summary t8_ccp_member if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Chinese Communist Party member") wvar(t8_weight)
local ++r
t1d_post_summary t8_income_expect if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Expected household income change") wvar(t8_weight)
local ++r
t1d_post_summary t8_job_expect if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Expected job stability or change") wvar(t8_weight)

* Prior devices, AI cognition, and AI practice in 2023.
local ++r
t1d_post_summary t8_phone if t1d_sample_linked == 1,   ///
    handle(`t1d_post') row(`r')                        ///
    desc("Phone ownership, 2023") wvar(t8_weight)
local ++r
t1d_post_summary t8_ihs_phone_value if t1d_sample_linked == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Phone value, 2023, IHS") wvar(t8_weight)
local ++r
t1d_post_summary t8_computer if t1d_sample_linked == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Computer ownership, 2023") wvar(t8_weight)
local ++r
t1d_post_summary t8_ihs_computer_value if t1d_sample_linked == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Computer value, 2023, IHS") wvar(t8_weight)
local ++r
t1d_post_summary t8_ai_awareness23 if t1d_sample_linked == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("AI awareness, 2023") wvar(t8_weight)
local ++r
t1d_post_summary t8_ai_familiarity_z if t1d_sample_linked == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("AI familiarity, 2023, SD") wvar(t8_weight)
local ++r
t1d_post_summary t8_prior_ai_use if t1d_sample_linked == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("AI use, 2023") wvar(t8_weight)

* Longitudinal economic outcomes. Equivalized income in 2024 already appears
* above and is therefore not repeated.
local ++r
t1d_post_summary t13_ihs_indinc22 if t13_sample_ind == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Individual income, 2022, IHS") wvar(t13_ai_weight)
local ++r
t1d_post_summary t13_ihs_indinc24 if t13_sample_ind == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Individual income, 2024, IHS") wvar(t13_ai_weight)
local ++r
t1d_post_summary t13_ihs_eqinc22 if t13_sample_hh == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Equivalized household income, 2022, IHS")   ///
    wvar(t13_hh_weight)
local ++r
t1d_post_summary t13_hours22_1000 if t13_sample_hours == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Annual work hours, 2022, thousands")        ///
    wvar(t13_ai_weight)
local ++r
t1d_post_summary t13_hours24_1000 if t13_sample_hours == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("Annual work hours, 2024, thousands")        ///
    wvar(t13_ai_weight)

* Institutional field variables in 2025.
local ++r
t1d_post_summary t15_industry_detail if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r') desc("Industry") wvar(t15_weight)
local ++r
t1d_post_summary t15_policy_intensity if t1d_sample_2025 == 1, ///
    handle(`t1d_post') row(`r')                        ///
    desc("AI policy promotion intensity") wvar(t15_weight)

postclose `t1d_post'


*--------------------------------------------------------------------*
* 5. EXPORT EXCEL AND WORD-READY TABLE 1
*--------------------------------------------------------------------*

global t1d_excel "$t1d_tables/Table1_compact_descriptive_statistics.xlsx"
global t1d_docx  "$t1d_tables/Table1_compact_descriptive_statistics.docx"

preserve
    use `t1d_table', clear
    sort row_order
    drop row_order
    format mean standard_deviation minimum median maximum %9.2f

    export excel using "$t1d_excel", sheet("Table 1") ///
        firstrow(variables) replace

    putdocx clear
    putdocx begin, landscape

    putdocx paragraph, halign(left)
    putdocx text ("Table 1. Summary statistics for variables used in the analysis"), ///
        bold

    putdocx table t1d = data(variable_label mean        ///
        standard_deviation minimum median maximum), varnames

    putdocx table t1d(1,1) = ("Variable")
    putdocx table t1d(1,2) = ("Mean")
    putdocx table t1d(1,3) = ("Standard deviation")
    putdocx table t1d(1,4) = ("Minimum")
    putdocx table t1d(1,5) = ("Median")
    putdocx table t1d(1,6) = ("Maximum")
    putdocx table t1d(1,.), bold
    putdocx table t1d(.,1), halign(left)
    putdocx table t1d(.,2), halign(right)
    putdocx table t1d(.,3), halign(right)
    putdocx table t1d(.,4), halign(right)
    putdocx table t1d(.,5), halign(right)
    putdocx table t1d(.,6), halign(right)

    putdocx paragraph
    putdocx text ("Notes: Means, standard deviations, and medians use the relevant survey weight. Minimum and maximum report the observed range. Binary-variable means are proportions. AI breadth and time include nonusers as category 0. Perceived-consequence measures are defined among users of the corresponding AI type. IHS denotes the inverse hyperbolic sine transformation. Region, employment and student position, hukou and residence, and industry are categorical controls; their numeric codes do not form substantive interval scales. Observation counts are omitted here and reported in the regression tables and appendix sample-flow table."), italic

    putdocx save "$t1d_docx", replace
restore


*--------------------------------------------------------------------*
* 6. FINAL AUDIT
*--------------------------------------------------------------------*

display as text "Compact descriptive-statistics workbook:"
display as result "$t1d_excel"
display as text "Word-ready Table 1:"
display as result "$t1d_docx"
display as text "Log file:"
display as result "$t1d_logs/15_table1_descriptive_statistics_tables2_5.log"

capture program drop t1d_post_summary
log close
