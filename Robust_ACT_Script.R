#### A - Individual Patient Data ####

# 1 - Recommended ACT target during surgery (seconds) : 
ACT_Target <- 400
# 2 - Values of measured ACTs of the patient (seconds) :
ACT_Values_Measured <- c(110, 445, 402, 502, 307, 447)
# 3 - Times of ACT measurements (minutes) :
ACT_Measurement_Times <- c(0.0, 5.4, 27.0, 56.4, 85.2, 113.4) 
# 4 - Patient weight (kg) :
Patient_Weight <- 85 
# 5 - Heparin boluses given (total UI per shot) :
Bolus_Given <- c(25000, 10000, 5000) 
# 6 - Times where the heparin boluses were given (minutes) :
Bolus_Times <- c(6.0, 31.8, 96.0) 
# 7 - Infusion rates of heparin infusions given to the patients (UI per hour) :
Infusion_Rates_Given <- c(0)
# 8 - Start times of heparin infusions (minutes) :
Infusion_Times <- c(0)
# 9 - Duration of given heparin infusions (minutes) :
Infusion_Durations <- c(0) 

#### B - Launch Function ####

# Launch continuous UFH strategy function:
Robust_ACT_Continuous(ACT_Target, ACT_Values_Measured, ACT_Measurement_Times, Patient_Weight,
                    Bolus_Given, Bolus_Times, Infusion_Rates_Given, Infusion_Times,
                    Infusion_Durations)

# Launch intermittent UFH strategy function:
Robust_ACT_Intermittent(ACT_Target, ACT_Values_Measured, ACT_Measurement_Times, Patient_Weight,
                       Bolus_Given, Bolus_Times, Infusion_Rates_Given, Infusion_Times,
                       Infusion_Durations)

#### C - Function creation ####

# Continuous UFH strategy function creation:
Robust_ACT_Continuous <- function(ACT_Target, ACT_Values_Measured, ACT_Measurement_Times,
                                Patient_Weight, Bolus_Given, Bolus_Times,
                                Infusion_Rates_Given, Infusion_Times,
                                Infusion_Durations) {
  
  #### Libraries required ####
  
  # Libraries required #
  packages = c("ggplot2", "MASS", "tidyr")
  
  # Load or install & load needed libraries #
  package.check <- lapply(
    packages,
    FUN = function(x) {
      if (!require(x, character.only = TRUE)) {
        install.packages(x, dependencies = TRUE)
        library(x, character.only = TRUE)
      }
    }
  )
  
  #### Function creation ####
  
  Pred_Robust <- function(phi, times, doses, TD, bw, IR, TDperf, Tinfu) {
    
    Ke = exp(-0.832) * exp(phi[1]) 
    ACT0 = exp(4.748) * exp(phi[2])
    EC50 = exp(9.846)
    Emax = exp(6.513) * exp(phi[3])
    
    A <- rep(0, length(times))
    
    B <- rep(0, length(times))
    
    for (i in 1:length(doses)) {
      
      A <- A + (doses[i] * exp((-Ke) * (times - TD[i]))) * (times > TD[i])
      
    }
    
    for (j in 1:length(TDperf)) {
      
      B1 <- IR[j] * (1/Ke) * (1 - exp((-Ke) * (times - TDperf[j])))
      
      B2 <- IR[j] * (1/Ke) * (1 - exp((-Ke) * Tinfu[j])) *
        exp((-Ke * (times - TDperf[j] - Tinfu[j])) *
              ( (times - TDperf[j]) > Tinfu[j] ))
      
      B <- B + (B1*( (times - TDperf[j]) <= Tinfu[j] ) * (times >= TDperf[j]) + 
                  B2 * ((times - TDperf[j]) > Tinfu[j] ))
      
    }
    
    ACT <- ACT0 + ((Emax * exp(-0.771 * log(bw/80)) * (A + B)) /
                     (EC50  + exp(-0.771 * log(bw/80)) * (A + B)))
    
    AB <- A+B
    
    rs <- list(ACT, AB)
    
    return(rs)
    
  }
  
  Distance_Robust <- function(eta, OBS, times, omega, bw, doses,
                              dosetime, sigma, dof, IR, TDperf, Tinfu) {
    
    PRED <- Pred_Robust(eta, times, doses, dosetime, bw, IR, TDperf, Tinfu) 
    
    Distance1 <- sum(0.5 * ((dof + 1) / 2) * log(1+(1/dof) * ((OBS - PRED[[1]])/(sigma * PRED[[1]]))^2))
    
    Distance2 <- 0.5 * eta %*% diag(1/omega) %*% eta
    
    return(Distance1 + Distance2)
    
  }
  
  #### Parameter initialization ####
  
  sigma <-  0.05 # Proportional error value
  
  dof <- 2.214 # Degrees of Freedom
  
  eta0 <- c(0, 0, 0)
  
  # Random Effects #
  
  om_Ke <- 0.174
  om_ACT0 <- 0.116
  om_Emax <- 0.292
  
  omega = c(om_Ke, om_ACT0, om_Emax)^2
  
  #### Modelization ####
  
  # Change minutes to hour #
  ACT_Measurement_Times <- ACT_Measurement_Times/60
  Bolus_Times <-Bolus_Times/60
  Infusion_Times <- Infusion_Times/60
  Infusion_Durations <- Infusion_Durations/60
  
  optimisation_robust <- optim(eta0, Distance_Robust, OBS = ACT_Values_Measured,
                               times = ACT_Measurement_Times, omega = omega,
                               bw = Patient_Weight,
                               doses = Bolus_Given, dosetime = Bolus_Times,
                               sigma = sigma, dof = dof, IR = Infusion_Rates_Given,
                               TDperf = Infusion_Times, Tinfu = Infusion_Durations)
  
  eta_opti <- optimisation_robust$par
  
  # Next loading dose (bolus) computation: A_Target #
  A_Target <- ((Patient_Weight/80)^(0.771)) * 
    (((ACT_Target - (exp(4.748) * exp(eta_opti[2]))) *  exp(9.846)) /
       ((exp(6.513) * exp(eta_opti[3])) - ACT_Target + exp(4.748) * exp(eta_opti[2])))
  
  ACT_Pred_Measure_Time <- ACT_Measurement_Times[length(ACT_Measurement_Times)]
  
  PRED <- Pred_Robust(eta_opti, ACT_Pred_Measure_Time,
                      Bolus_Given, Bolus_Times, Patient_Weight,
                      Infusion_Rates_Given, Infusion_Times,
                      Infusion_Durations)
  
  if (PRED[[1]] < ACT_Target) {
    
    LD_New <- A_Target - PRED[[2]]
    Perf_Time_New <- ACT_Measurement_Times[length(ACT_Measurement_Times)]
    
  } else if (PRED[[1]] >= ACT_Target) {
    
    LD_New <- 0
    Perf_Time_New <- ACT_Measurement_Times[length(ACT_Measurement_Times)] +
      ((log(PRED[[2]]) - log(A_Target)) /
         (exp(-0.832) * exp(eta_opti[1])))
    
  }
  
  # New infusion #
  IR_New <- (exp(-0.832) * exp(eta_opti[1])) * A_Target
  
  Infusion_Rates_Given_2 <- c(Infusion_Rates_Given, IR_New)
  Infusion_Times2 <- c(Infusion_Times, Perf_Time_New)
  Infusion_Durations2 <- c(Infusion_Durations, 2000)
  
  # New boluses #
  Bolus_Given2 <- c(Bolus_Given, LD_New)
  Bolus_Times2 <- c(Bolus_Times,
                    ACT_Measurement_Times[length(ACT_Measurement_Times)])
  
  #### Plot data ####
  
  TimeLine <- seq(min(ACT_Measurement_Times), (max(ACT_Measurement_Times) + 4), 0.01)
  
  OBS_graph <- Pred_Robust(eta_opti, TimeLine,
                           Bolus_Given2, Bolus_Times2, Patient_Weight,
                           Infusion_Rates_Given_2, Infusion_Times2,
                           Infusion_Durations2)
  
  # Differentiate observed versus predicted # 
  predVobs <- ifelse(TimeLine > ACT_Measurement_Times[length(ACT_Measurement_Times)]-0.01,
                     1, 0)
  
  Point_Plot <- data.frame(ACT_mesures = ACT_Values_Measured,
                           M_Times = ACT_Measurement_Times,
                           Nombre_ACT = length(ACT_Values_Measured))
  
  Line_Plot <- data.frame(TimeLine = TimeLine,
                          Observations = OBS_graph[[1]],
                          Predobs = predVobs)
  
  #### Uncertainty measure ####
  
  n <- 1000
  
  optimisation_robust <- optim(eta0, Distance_Robust, OBS = ACT_Values_Measured,
                               times = ACT_Measurement_Times, omega = omega,
                               bw = Patient_Weight,
                               doses = Bolus_Given, dosetime = Bolus_Times,
                               sigma = sigma, dof = dof, IR = Infusion_Rates_Given,
                               TDperf = Infusion_Times, Tinfu = Infusion_Durations, 
                               hessian = TRUE)
  
  eta_opti <- optimisation_robust$par
  
  MatVarCov <- solve(optimisation_robust$hessian)
  
  ETA <- mvrnorm(n, optimisation_robust$par, MatVarCov)
  
  OBS_ribbon2 <- c()
  
  LD_95CI <- c()
  IR_95CI <- c()
  IR_Time_95CI <- c()
  
  for (i in 1:n) {
    
    OBS_ribbon <- Pred_Robust(ETA[i,], TimeLine,
                              Bolus_Given2, Bolus_Times2, Patient_Weight,
                              Infusion_Rates_Given_2, Infusion_Times2,
                              Infusion_Durations2)
    
    OBS_ribbon2 <- rbind(OBS_ribbon2, OBS_ribbon[[1]])
    
    # For confidence intervals of LD, IR et IR times #
    A_TargetCI <- ((Patient_Weight/80)^(0.771)) * 
      (((ACT_Target - (exp(4.748) * exp(ETA[i,2]))) *  exp(9.846)) /
         ((exp(6.513) * exp(ETA[i,3])) - ACT_Target + exp(4.748) * exp(ETA[i,2])))
    
    ACT_Pred_Measure_Time2 <- ACT_Measurement_Times[length(ACT_Measurement_Times)]
    
    PREDCI <- Pred_Robust(ETA[i,], ACT_Pred_Measure_Time2,
                          Bolus_Given, Bolus_Times, Patient_Weight,
                          Infusion_Rates_Given, Infusion_Times,
                          Infusion_Durations)
    
    if (PREDCI[[1]] < ACT_Target) {
      
      LD_New2 <- A_TargetCI - PREDCI[[2]]
      Perf_Time_New2 <- ACT_Measurement_Times[length(ACT_Measurement_Times)]
      
    } else if (PREDCI[[1]] >= ACT_Target) {
      
      LD_New2 <- 0
      Perf_Time_New2 <- ACT_Measurement_Times[length(ACT_Measurement_Times)] +
        ((log(PREDCI[[2]]) - log(A_TargetCI)) /
           (exp(-0.832) * exp(ETA[i,1])))
      
    }
    
    IR_New2 <- (exp(-0.832) * exp(ETA[i,1])) * A_TargetCI
    
    LD_95CI <- rbind(LD_95CI, LD_New2)
    IR_95CI <- rbind(IR_95CI, IR_New2)
    IR_Time_95CI <- rbind(IR_Time_95CI, Perf_Time_New2)
    
  }
  
  Uncertainty_data = data.frame(M_Times = rep(TimeLine, n),
                                ID = rep(c(1:n), each = length(TimeLine)),
                                Uncertainty = as.vector(t(OBS_ribbon2)))
  
  Udata_wide <- Uncertainty_data %>% spread(key = M_Times, value = Uncertainty)
  
  # ACT Intervals #
  q5 <-  apply(Udata_wide[2 : length(Udata_wide)], 2, quantile, probs = 0.05, na.rm = TRUE )
  q95 <- apply(Udata_wide[2 : length(Udata_wide)], 2 , quantile, probs = 0.95, na.rm = TRUE )
  q25 <-  apply(Udata_wide[2 : length(Udata_wide)], 2, quantile, probs = 0.25, na.rm = TRUE )
  q75 <-  apply(Udata_wide[2 : length(Udata_wide)], 2, quantile, probs = 0.75, na.rm = TRUE )
  q5 = as.numeric(q5); q95 = as.numeric(q95); 
  q25 = as.numeric(q25); q75 = as.numeric(q75)
  Udata_CI <- data.frame(q5, q95, q75, q25, TimeLine)
  
  # Heparin doses CI 95% #
  q5LD <-  apply(LD_95CI, 2,
                 quantile, probs = 0.05, na.rm = TRUE )
  q95LD <- apply(LD_95CI, 2 ,
                 quantile, probs = 0.95, na.rm = TRUE )
  
  q5IR <-  apply(IR_95CI, 2,
                 quantile, probs = 0.05, na.rm = TRUE )
  q95IR <-  apply(IR_95CI, 2,
                  quantile, probs = 0.95, na.rm = TRUE )
  
  q5TIR <- apply(IR_Time_95CI, 2,
                 quantile, probs = 0.05, na.rm = TRUE )
  q95TIR <-  apply(IR_Time_95CI, 2,
                   quantile, probs = 0.95, na.rm = TRUE )
  
  #### Add information text ####
  
  label <- data.frame(
    x = c(max(Line_Plot$TimeLine) - (max(Line_Plot$TimeLine)/2),
          max(Line_Plot$TimeLine) - (max(Line_Plot$TimeLine)/2),
          max(Line_Plot$TimeLine) - (max(Line_Plot$TimeLine)/2)),
    y = c(min(Line_Plot$Observations) + (max(Line_Plot$Observations)/10)*2, 
          min(Line_Plot$Observations) + (max(Line_Plot$Observations)/10),
          min(Line_Plot$Observations)),
    label = c(if(LD_New == 0) {
      
      paste0("No new loading dose")
      
    } else {
      
      paste0("New loading dose = ", round(LD_New, 2),
             " UI, 95% CI: [", round(q5LD,2), "-", round(q95LD,2), "]")
    },
    
    paste0("New infusion rate = ", round(IR_New, 2),
           " UI/h, 95% CI: [", round(q5IR,2), "-", round(q95IR,2), "]"),
    
    if ((Perf_Time_New - ACT_Measurement_Times[length(ACT_Measurement_Times)]) != 0) {
      
      paste0("Restart infusion in ", round((Perf_Time_New - ACT_Measurement_Times[length(ACT_Measurement_Times)])*60, 2),
             " minutes, 95% CI: [", round((q5TIR - ACT_Measurement_Times[length(ACT_Measurement_Times)])*60, 2),
             "-", round((q95TIR - ACT_Measurement_Times[length(ACT_Measurement_Times)])*60, 2), "]")
      
    } else {
      
      paste0("Restart infusion now")
      
    })
    
  )
  
  # Add new IR time indication arrow, with offset position #
  
  IR_Arrow <- data.frame(
    x = c(Perf_Time_New, Perf_Time_New),
    y = c((Udata_CI$q5[which.min(abs(Udata_CI$TimeLine - Perf_Time_New))]) - 50,
          Udata_CI$q5[which.min(abs(Udata_CI$TimeLine - Perf_Time_New))] - 10)
  )
  
  # Arrow text disposition #
  minArrowy <- min(IR_Arrow$y)
  # Arrow text text #
  name <- "Restart\n infusion"
  
  #### Plot ####
  
  return(ggplot() +
           geom_hline(yintercept = ACT_Target, linetype= "dashed",
                      color = "black", size= 0.5) +
           geom_ribbon(data = Udata_CI, aes(ymin= q5, ymax= q95, x= TimeLine) ,
                       fill = "#FFCC33" , alpha = 0.4) +
           geom_ribbon(data = Udata_CI, aes(ymin= q25, ymax= q75, x= TimeLine) ,
                       fill = "#FFCC33" , alpha = 0.4) +
           geom_line(data = subset(Line_Plot, Predobs == 0),
                     aes(x = TimeLine, y = Observations), size = 1.1, color = "blue") +
           geom_line(data = subset(Line_Plot, Predobs == 1),
                     aes(x = TimeLine, y = Observations), size = 1.1, color = "#CC3333",
                     linetype = "dashed") +
           geom_point(data = Point_Plot, aes(x = M_Times, y = ACT_Values_Measured),
                      color = "darkred", size = 1.5, shape = 21, stroke = 1.2) +
           theme_bw() +
           theme(axis.text.x = element_text(face="bold", size= 11),
                 axis.text.y = element_text(face="bold", size= 11)) +
           xlab(label = "Time (h)") +
           ylab(lab = "ACT (seconds)") +
           theme(axis.title.x = element_text(face = "bold"),
                 axis.title.y = element_text(face = "bold")) +
           geom_label(data = label, aes(label = label, x = x, y = y), color = "black",
                      size = 3.5) +
           geom_path(data = IR_Arrow, aes(x = x, y = y), color = "darkred",
                     arrow = arrow(length = unit(0.25, "cm")), size = 1) +
           geom_text(aes(x = Perf_Time_New, y = (minArrowy - 20),
                         label = name), color = "darkred"))
  
}

# Intermittent UFH strategy function creation:
Robust_ACT_Intermittent <- function(ACT_Target, ACT_Values_Measured, ACT_Measurement_Times,
                                 Patient_Weight, Bolus_Given, Bolus_Times,
                                 Infusion_Rates_Given, Infusion_Times,
                                 Infusion_Durations) {
  
  #### Libraries required ####
  
  # Libraries required #
  packages = c("ggplot2", "MASS", "tidyr")
  
  # Load or install & load needed libraries #
  package.check <- lapply(
    packages,
    FUN = function(x) {
      if (!require(x, character.only = TRUE)) {
        install.packages(x, dependencies = TRUE)
        library(x, character.only = TRUE)
      }
    }
  )
  
  #### Function creation ####
  
  Pred_Robust <- function(phi, times, doses, TD, bw, IR, TDperf, Tinfu) {
    
    Ke = exp(-0.832) * exp(phi[1]) 
    ACT0 = exp(4.748) * exp(phi[2])
    EC50 = exp(9.846)
    Emax = exp(6.513) * exp(phi[3])
    
    A <- rep(0, length(times))
    
    B <- rep(0, length(times))
    
    for (i in 1:length(doses)) {
      
      A <- A + (doses[i] * exp((-Ke) * (times - TD[i]))) * (times > TD[i])
      
    }
    
    for (j in 1:length(TDperf)) {
      
      B1 <- IR[j] * (1/Ke) * (1 - exp((-Ke) * (times - TDperf[j])))
      
      B2 <- IR[j] * (1/Ke) * (1 - exp((-Ke) * Tinfu[j])) *
        exp((-Ke * (times - TDperf[j] - Tinfu[j])) *
              ((times - TDperf[j]) > Tinfu[j] ))
      
      B <- B + (B1*( (times - TDperf[j]) <= Tinfu[j] ) * (times >= TDperf[j]) + 
                  B2 * ((times - TDperf[j]) > Tinfu[j] ))
      
    }
    
    ACT <- ACT0 + ((Emax * exp(-0.771 * log(bw/80)) * (A + B)) /
                     (EC50  + exp(-0.771 * log(bw/80)) * (A + B)))
    
    AB <- A+B
    
    rs <- list(ACT, AB)
    
    return(rs)
    
  }
  
  Distance_Robust <- function(eta, OBS, times, omega, bw, doses,
                              dosetime, sigma, dof, IR, TDperf, Tinfu) {
    
    PRED <- Pred_Robust(eta, times, doses, dosetime, bw, IR, TDperf, Tinfu) 
    
    Distance1 <- sum(0.5 * ((dof + 1) / 2) * log(1+(1/dof) * ((OBS - PRED[[1]])/(sigma * PRED[[1]]))^2))
    
    Distance2 <- 0.5 * eta %*% diag(1/omega) %*% eta
    
    return(Distance1 + Distance2)
    
  }
  
  #### Parameter initialization ####
  
  sigma <-  0.05 # Proportional error value
  
  dof <- 2.214 # Degrees of Freedom
  
  eta0 <- c(0, 0, 0)
  
  # Random Effects #
  
  om_Ke <- 0.174
  om_ACT0 <- 0.116
  om_Emax <- 0.292
  
  omega = c(om_Ke, om_ACT0, om_Emax)^2
  
  # Bolus scenario settings #
  
  deltaT <- 0.75
  
  #### Modelization ####
  
  # Change minutes to hour #
  ACT_Measurement_Times <- ACT_Measurement_Times/60
  Bolus_Times <- Bolus_Times/60
  Infusion_Times <- Infusion_Times/60
  Infusion_Durations <- Infusion_Durations/60
  
  optimisation_robust <- optim(eta0, Distance_Robust, OBS = ACT_Values_Measured,
                               times = ACT_Measurement_Times, omega = omega,
                               bw = Patient_Weight,
                               doses = Bolus_Given, dosetime = Bolus_Times,
                               sigma = sigma, dof = dof, IR = Infusion_Rates_Given,
                               TDperf = Infusion_Times, Tinfu = Infusion_Durations)
  
  eta_opti <- optimisation_robust$par
  
  # Next loading dose (bolus) computation: A_Target #
  A_Target <- ((Patient_Weight/80)^(0.771)) * 
    (((ACT_Target - (exp(4.748) * exp(eta_opti[2]))) *  exp(9.846)) /
       ((exp(6.513) * exp(eta_opti[3])) - ACT_Target + exp(4.748) * exp(eta_opti[2])))
  
  ACT_Pred_Measure_Time <- ACT_Measurement_Times[length(ACT_Measurement_Times)]
  
  PRED <- Pred_Robust(eta_opti, ACT_Pred_Measure_Time,
                      Bolus_Given, Bolus_Times, Patient_Weight,
                      Infusion_Rates_Given, Infusion_Times,
                      Infusion_Durations)
  
  if (PRED[[1]] < ACT_Target) {
    
    LD_New <- A_Target - PRED[[2]]
    Bolus_Time_New <- ACT_Measurement_Times[length(ACT_Measurement_Times)]
    
  } else if (PRED[[1]] >= ACT_Target) {
    
    LD_New <- 0
    Bolus_Time_New <- ACT_Measurement_Times[length(ACT_Measurement_Times)] +
      ((log(PRED[[2]]) - log(A_Target)) /
         (exp(-0.832) * exp(eta_opti[1])))
    
  }
  
  #### Debut du if() #### 
  
  # New infusion #
  # IR_New <- (exp(-0.832) * exp(eta_opti[1])) * A_Target
  Bolus_New <- A_Target * (exp(exp(-0.832 + eta_opti[1]) * deltaT) - 1)
  
  # BOLUS_New <- A_Target * (exp(exp(-0.832 + eta_opti[1]) * deltaT) - 1)
  
  Infusion_Rates_Given_2 <- c(Infusion_Rates_Given, Bolus_New)
  Bolus_Time_New2 <- c(Infusion_Times, Bolus_Time_New)
  Infusion_Durations2 <- c(Infusion_Durations, 0)
  
  # New boluses #
  Bolus_Given2 <- c(Bolus_Given, LD_New + Bolus_New, rep(Bolus_New, length(seq(Bolus_Time_New + deltaT,5,deltaT))))
  Bolus_Times2 <- c(Bolus_Times, Bolus_Time_New, seq(Bolus_Time_New + deltaT, 5, deltaT))
  
  #### Plot data ####
  
  TimeLine <- seq(min(ACT_Measurement_Times), (max(ACT_Measurement_Times) + 4), 0.01)
  
  OBS_graph <- Pred_Robust(eta_opti, TimeLine,
                           Bolus_Given2, Bolus_Times2, Patient_Weight,
                           Infusion_Rates_Given_2 * 0, Bolus_Time_New2,
                           Infusion_Durations2)
  
  # Differentiate observed versus predicted # 
  predVobs <- ifelse(TimeLine > ACT_Measurement_Times[length(ACT_Measurement_Times)] - 0.01,
                     1, 0)
  
  Point_Plot <- data.frame(ACT_mesures = ACT_Values_Measured,
                           M_Times = ACT_Measurement_Times,
                           Nombre_ACT = length(ACT_Values_Measured))
  
  Line_Plot <- data.frame(TimeLine = TimeLine,
                          Observations = OBS_graph[[1]],
                          Predobs = predVobs)
  
  #### Uncertainty measure ####
  
  n <- 1000
  
  optimisation_robust <- optim(eta0, Distance_Robust, OBS = ACT_Values_Measured,
                               times = ACT_Measurement_Times, omega = omega,
                               bw = Patient_Weight,
                               doses = Bolus_Given, dosetime = Bolus_Times,
                               sigma = sigma, dof = dof, IR = Infusion_Rates_Given,
                               TDperf = Infusion_Times, Tinfu = Infusion_Durations, 
                               hessian = TRUE)
  
  eta_opti <- optimisation_robust$par
  
  MatVarCov <- solve(optimisation_robust$hessian)
  
  ETA <- mvrnorm(n, optimisation_robust$par, MatVarCov)
  
  OBS_ribbon2 <- c()
  
  LD_95CI <- c()
  IR_95CI <- c()
  IR_Time_95CI <- c()
  
  for (i in 1:n) {
    
    OBS_ribbon <- Pred_Robust(ETA[i,], TimeLine,
                              Bolus_Given2, Bolus_Times2, Patient_Weight,
                              Infusion_Rates_Given_2, Bolus_Time_New2,
                              Infusion_Durations2)
    
    OBS_ribbon2 <- rbind(OBS_ribbon2, OBS_ribbon[[1]])
    
    # For confidence intervals of LD, IR et IR times #
    A_TargetCI <- ((Patient_Weight/80)^(0.771)) * 
      (((ACT_Target - (exp(4.748) * exp(ETA[i,2]))) *  exp(9.846)) /
         ((exp(6.513) * exp(ETA[i,3])) - ACT_Target + exp(4.748) * exp(ETA[i,2])))
    
    ACT_Pred_Measure_Time2 <- ACT_Measurement_Times[length(ACT_Measurement_Times)]
    
    PREDCI <- Pred_Robust(ETA[i,], ACT_Pred_Measure_Time2,
                          Bolus_Given, Bolus_Times, Patient_Weight,
                          Infusion_Rates_Given, Infusion_Times,
                          Infusion_Durations)
    
    if (PREDCI[[1]] < ACT_Target) {
      
      LD_New2 <- A_TargetCI - PREDCI[[2]]
      Bolus_Time_New2 <- ACT_Measurement_Times[length(ACT_Measurement_Times)]
      
    } else if (PREDCI[[1]] >= ACT_Target) {
      
      LD_New2 <- 0
      Bolus_Time_New2 <- ACT_Measurement_Times[length(ACT_Measurement_Times)] +
        ((log(PREDCI[[2]]) - log(A_TargetCI)) /
           (exp(-0.832) * exp(ETA[i,1])))
      
    }
    
    Bolus_New2 <- (exp(-0.832) * exp(ETA[i,1])) * A_TargetCI
    
    LD_95CI <- rbind(LD_95CI, LD_New2)
    IR_95CI <- rbind(IR_95CI, Bolus_New2)
    IR_Time_95CI <- rbind(IR_Time_95CI, Bolus_Time_New2)
    
  }
  
  Uncertainty_data = data.frame(M_Times = rep(TimeLine, n),
                                ID = rep(c(1:n), each = length(TimeLine)),
                                Uncertainty = as.vector(t(OBS_ribbon2)))
  
  Udata_wide <- Uncertainty_data %>% spread(key = M_Times, value = Uncertainty)
  
  # ACT Intervals #
  q5 <-  apply(Udata_wide[2 : length(Udata_wide)], 2, quantile, probs = 0.05, na.rm = TRUE )
  q95 <- apply(Udata_wide[2 : length(Udata_wide)], 2 , quantile, probs = 0.95, na.rm = TRUE )
  q25 <-  apply(Udata_wide[2 : length(Udata_wide)], 2, quantile, probs = 0.25, na.rm = TRUE )
  q75 <-  apply(Udata_wide[2 : length(Udata_wide)], 2, quantile, probs = 0.75, na.rm = TRUE )
  q5 = as.numeric(q5); q95 = as.numeric(q95); 
  q25 = as.numeric(q25); q75 = as.numeric(q75)
  Udata_CI <- data.frame(q5, q95, q75, q25, TimeLine)
  
  # Heparin doses CI 95% #
  q5LD <-  apply(LD_95CI, 2,
                 quantile, probs = 0.05, na.rm = TRUE )
  q95LD <- apply(LD_95CI, 2 ,
                 quantile, probs = 0.95, na.rm = TRUE )
  
  q5IR <-  apply(IR_95CI, 2,
                 quantile, probs = 0.05, na.rm = TRUE )
  q95IR <-  apply(IR_95CI, 2,
                  quantile, probs = 0.95, na.rm = TRUE )
  
  q5TIR <- apply(IR_Time_95CI, 2,
                 quantile, probs = 0.05, na.rm = TRUE )
  q95TIR <-  apply(IR_Time_95CI, 2,
                   quantile, probs = 0.95, na.rm = TRUE )
  
  #### Add information text ####
  
  label <- data.frame(
    x = c(max(Line_Plot$TimeLine) - (max(Line_Plot$TimeLine)/2),
          max(Line_Plot$TimeLine) - (max(Line_Plot$TimeLine)/2),
          max(Line_Plot$TimeLine) - (max(Line_Plot$TimeLine)/2)),
    y = c(min(Line_Plot$Observations) + (max(Line_Plot$Observations)/10)*2, 
          min(Line_Plot$Observations) + (max(Line_Plot$Observations)/10),
          min(Line_Plot$Observations)),
    label = c( 
      
      if(LD_New == 0) {
        
        paste0("No new loading dose")
        
      } else {
        
        paste0("New loading dose = ", round(LD_New, 2),
               " UI, 95% CI: [", round(q5LD,2), "-", round(q95LD,2), "]")
        
      },
      
      paste0("New maintenance bolus = ", round(Bolus_New, 2),
             " UI/h, 95% CI: [", round(q5IR,2), "-", round(q95IR,2), "]"),
      
      if((Bolus_Time_New - ACT_Measurement_Times[length(ACT_Measurement_Times)]) != 0) {
        
        paste0("Maintenance bolus in ", round((Bolus_Time_New - ACT_Measurement_Times[length(ACT_Measurement_Times)])*60, 2),
               " minutes, 95% CI: [", round((q5TIR - ACT_Measurement_Times[length(ACT_Measurement_Times)])*60, 2),
               "-", round((q95TIR - ACT_Measurement_Times[length(ACT_Measurement_Times)])*60, 2), "]")
        
      } else {
        
        paste0("Maintenance bolus now")
        
      }))
  
  # Add new IR time indication arrow, with offset position #
  
  IR_Arrow <- data.frame(
    x = c(Bolus_Time_New, Bolus_Time_New),
    y = c((Udata_CI$q5[which.min(abs(Udata_CI$TimeLine - Bolus_Time_New))]) - 60,
          Udata_CI$q5[which.min(abs(Udata_CI$TimeLine - Bolus_Time_New))] - 20))
  
  
  
  # Diff de 40 pour taille de fleche parfait
  
  # Arrow text disposition #
  minArrowy <- min(IR_Arrow$y)
  # Arrow text text #
  name <- "Start\n maintenance bolus"
  
  #### Plot ####
  
  return(ggplot() +
           geom_hline(yintercept = ACT_Target, linetype= "dashed",
                      color = "black", size= 0.5) +
           geom_ribbon(data = Udata_CI, aes(ymin= q5, ymax= q95, x= TimeLine) ,
                       fill = "#FFCC33" , alpha = 0.4) +
           geom_ribbon(data = Udata_CI, aes(ymin= q25, ymax= q75, x= TimeLine) ,
                       fill = "#FFCC33" , alpha = 0.4) +
           geom_line(data = subset(Line_Plot, Predobs == 0),
                     aes(x = TimeLine, y = Observations), size = 1.1, color = "blue") +
           geom_line(data = subset(Line_Plot, Predobs == 1),
                     aes(x = TimeLine, y = Observations), size = 1.1, color = "#CC3333",
                     linetype = "dashed") +
           geom_point(data = Point_Plot, aes(x = M_Times, y = ACT_Values_Measured),
                      color = "darkred", size = 1.5, shape = 21, stroke = 1.2) +
           theme_bw() +
           theme(axis.text.x = element_text(face="bold", size= 11),
                 axis.text.y = element_text(face="bold", size= 11)) +
           xlab(label = "Time (h)") +
           ylab(lab = "ACT (seconds)") +
           theme(axis.title.x = element_text(face = "bold"),
                 axis.title.y = element_text(face = "bold")) +
           geom_label(data = label, aes(label = label, x = x, y = y), color = "black",
                      size = 3.5) +
           geom_path(data = IR_Arrow, aes(x = x, y = y), color = "darkred",
                     arrow = arrow(length = unit(0.25, "cm")), size = 1) +
           geom_text(aes(x = Bolus_Time_New, y = (minArrowy - 25),
                         label = name), color = "darkred"))
  
}

