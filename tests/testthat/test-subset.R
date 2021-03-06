context("Test subset")

setup(RNGversion("3.5.3"))
teardown({
  cur_R_version <- trimws(substr(R.version.string, 10, 16))
  RNGversion(cur_R_version)
})

test_that("Test against reference results - numeric dates", {
    skip_on_cran()

    ## simulate basic epicurve
    dat <- c(0, 2, 2, 3, 3, 5, 5, 5, 6, 6, 6, 6)
    i <- incidence::incidence(dat)


    ## example with a function for SI
    si <- distcrete::distcrete("gamma", interval = 1L,
                    shape = 1.5,
                    scale = 2, w = 0)

    set.seed(1)
    pred_1 <- project(i, runif(100, 0.8, 1.9), si, n_days = 30)

    subset_1 <- subset(pred_1, from = 15, to = 20, sim = 1:10)
    attributes(subset_1)$class <- attributes(subset_1)$class[(1:2)]
    subset_2 <- subset(pred_1, from = 15, sim = c(TRUE, FALSE))
    attributes(subset_2)$class <- attributes(subset_2)$class[(1:2)]
    subset_3 <- subset(pred_1, to = 15, sim = c(TRUE, FALSE))
    attributes(subset_3)$class <- attributes(subset_3)$class[(1:2)]

    expect_identical(pred_1[], pred_1)
    expect_equal_to_reference(subset_1, file = "rds/subset_1.rds", update = FALSE)
    expect_equal_to_reference(subset_2, file = "rds/subset_2.rds", update = FALSE)
    expect_equal_to_reference(subset_3, file = "rds/subset_3.rds", update = FALSE)
    expect_error(subset(pred_1, from = 1, to = 0), "No data retained.")

})





test_that("Test against reference results - Date dates", {
    skip_on_cran()

    ## simulate basic epicurve
    day <- as.Date("1982-01-01")
    dat <- day + c(0, 2, 2, 3, 3, 5, 5, 5, 6, 6, 6, 6)
    i <- incidence::incidence(dat)


    ## example with a function for SI
    si <- distcrete::distcrete("gamma", interval = 1L,
                    shape = 1.5,
                    scale = 2, w = 0)

    set.seed(1)
    pred_1 <- project(i, runif(100, 0.8, 1.9), si, n_days = 30)

    subset_1 <- subset(pred_1, from = day + 15, to = day + 20, sim = 1:10)
    attributes(subset_1)$class <- attributes(subset_1)$class[(1:2)]
    subset_2 <- subset(pred_1, from = day + 15, sim = c(TRUE, FALSE))
    attributes(subset_2)$class <- attributes(subset_2)$class[(1:2)]
    subset_3 <- subset(pred_1, to = day + 15, sim = c(TRUE, FALSE))
    attributes(subset_3)$class <- attributes(subset_3)$class[(1:2)]

    expect_identical(pred_1[], pred_1)
    expect_equal_to_reference(subset_1, file = "rds/subset_Date_1.rds", update = FALSE)
    expect_equal_to_reference(subset_2, file = "rds/subset_Date_2.rds", update = FALSE)
    expect_equal_to_reference(subset_3, file = "rds/subset_Date_3.rds", update = FALSE)

})


