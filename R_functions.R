#################################################################################
##                                                                             ##
## Input table « tab » with the P dynamic predictions to compare:              ##
##_____________________________________________________________________________##
## ID | Time-to-event | Event | Landmark times | Dyn.pred.1 | ... | Dyn.pred.P ##
##_____________________________________________________________________________##
##  1 |           9.5 |     0 |            0.5 |       0.21 | ... |       0.13 ##
##  1 |           9.5 |     0 |            1.0 |       0.19 | ... |       0.11 ## 
##  1 |           9.5 |     0 |            2.0 |       0.23 | ... |       0.17 ##
##  1 |           9.5 |     0 |            4.0 |       0.17 | ... |       0.20 ##
##  7 |           5.2 |     1 |            0.5 |       0.51 | ... |       0.40 ##
##  7 |           5.2 |     1 |            1.0 |       0.64 | ... |       0.42 ##
##  7 |           5.2 |     1 |            2.0 |       0.65 | ... |       0.39 ##
##  7 |           5.2 |     1 |            4.0 |       0.70 | ... |       0.45 ##
##  . |             . |     . |              . |          . |  .  |          . ##
##  . |             . |     . |              . |          . |  .  |          . ##
##  . |             . |     . |              . |          . |  .  |          . ##
##_____________________________________________________________________________##
##                                                                             ##
## Input « horizon » denotes the horizon for which the dynamic predictions     ##
## have been computed.                                                         ##
##                                                                             ##
## Inputs « nb_boot » and « nb_ind_boot » refer respectively to the number of  ##
## bootstrap and the number of subjects taken into account to compute the      ##
## parameters of the gamma distribution.                                       ##
##                                                                             ##
#################################################################################

#Importing the necessary libraries
library(lcmm)
library(timeROC)
library(survival)
library(scmamp) ## available at "https://github.com/b0rxa/scmamp"
library(survminer)
library(survival)
library(ggplot2)

#### > sessionInfo()
#### R version 4.0.5 (2021-03-31)
#### Platform: x86_64-w64-mingw32/x64 (64-bit)
#### Running under: Windows >= 8 x64 (build 9200)
#### 
#### Matrix products: default
#### 
#### locale:
#### [1] LC_COLLATE=French_France.1252  LC_CTYPE=French_France.1252   
#### [3] LC_MONETARY=French_France.1252 LC_NUMERIC=C                  
#### [5] LC_TIME=French_France.1252    
#### 
#### attached base packages:
#### [1] parallel  stats     graphics  grDevices utils     datasets  methods   base     
#### 
#### other attached packages:
#### [1] survminer_0.4.9 ggpubr_0.4.0    ggplot2_3.3.3   scmamp_0.2.55   timeROC_0.4    
#### [6] lcmm_1.9.2      survival_3.2-10

###############################################
###############################################
##                                           ##
##              AUC computation              ##
##                                           ##
###############################################
###############################################

## This function allows to compute the different dynamic AUCs 
## for each prediction at each landmark time.

AUC_comp <- function(tab,horizon){
  
  nb_dyn_pred <- ncol(tab[,5:ncol(tab)])
  n <- length(unique(tab[,1]))
  land_time <- unique(tab[,4])
  nb_land_time <- length(unique(tab[,4]))
  
  matrixstat <- array(rep(NA,nb_land_time*3), dim = c(nb_land_time,3))
  colnames(matrixstat) <- c("Cases (s,s+t)","Controls (s,s+t)","Censored (s,s+t)")
  rownames(matrixstat) <- (paste0("s=",land_time))
  
  AUC <- array(rep(NA,nb_land_time*nb_dyn_pred), dim = c(nb_land_time,nb_dyn_pred))
  colnames(AUC) <- colnames(tab[5:ncol(tab)])
  rownames(AUC) <- paste0("s=",land_time)
  
  matiidAUC <- array(rep(NA,nb_land_time*n*nb_dyn_pred), 
                     dim = c(nb_land_time,n,nb_dyn_pred))
  rownames(matiidAUC) <- (paste0("s=",land_time))
  
  
  #AUC computation at each landmark time
  for(t in 1:nb_land_time){
    
    s <- land_time[t]
    #Landmark time database
    tab_lan <- tab[which(tab[,2] > s & tab[,4] == s),]
    #Time-to-event vector
    T_s <- tab_lan[,2] - s 
    #Event vector
    tab_lan$delta_s <- 0
    tab_lan$delta_s[which(tab_lan[,2]>s & tab_lan[,2]<=(s+t) & tab_lan[,3]==1)] <- 1
    delta_s <- tab_lan$delta_s
    #Predictions table
    prediction <- matrix(NA, nrow = length(delta_s), ncol = nb_dyn_pred)
    colnames(prediction) <- paste0("predictions_", 1:nb_dyn_pred, "_s")
    for(m in 5:(5+(nb_dyn_pred-1))){
      prediction[,m-4] <- tab_lan[,m]
    }
    indrisk <- unique(tab_lan[,1])
    
    for(m in 1:nb_dyn_pred){
      
      AUC_timeROC <- NULL
      AUC_timeROC <- timeROC(T = T_s, delta = delta_s, marker = prediction[,m], 
                             cause = 1, weighting="marginal",times=c(horizon),
                             iid=TRUE)
      #AUC estimator
      AUC[t,m] <- AUC_timeROC$AUC[2] 
      #AUC iid decomposition
      matiidAUC[t,,m] <- c( rep(0,n-AUC_timeROC$n),
                            AUC_timeROC$inference$mat_iid_rep_1[,2]) 
    }
    
    matrixstat[t,] <- AUC_timeROC$Stats[2,]
    
  }
  
  return(list(AUC=AUC, stats=matrixstat, mat_iid=matiidAUC))
  
}


################################################
################################################
##                                            ##
##              Reference choice              ##
##                                            ##
################################################
################################################

## It returns the dynamic prediction chosen as the one differing most from the others.

AUC_ref = function(tab,horizon){
  
  tabAUC <- AUC_comp(tab,horizon)
  nb_dyn_pred <- ncol(tabAUC$AUC)
  
  diff_sum <- array(rep(0,nb_dyn_pred), dim = c(1,nb_dyn_pred))
  colnames(diff_sum) <- c(colnames(tabAUC$AUC))
  
  for(i in 1:nb_dyn_pred){
    for(j in 1:nb_dyn_pred){
      if(i!=j){
        diff_sum[1,i] <- diff_sum[1,i]+sum(abs(tabAUC$AUC[,i]-tabAUC$AUC[,j]))
      }
    }
  }
  
  return(colnames(diff_sum)[which.max(diff_sum)])
  
}


####################################################
####################################################
##                                                ##
##              Parameter z in gamma              ##
##                                                ##
####################################################
####################################################

## This function calculates the parameters of the gamma distribution 
## of the test statistic.

z_gammma  <-  function(tab,horizon,nb_boot,nb_ind_boot){
  
  nb_dyn_pred <- ncol(tab[,5:ncol(tab)])
  n <- length(unique(tab[,1]))
  land_time <- unique(tab[,4])
  nb_land_time <- length(unique(tab[,4]))
  
  #Distribution matrix of subjects in each interval (s,s+t], initialization
  matrixstat <- array(rep(NA,nb_land_time*3*nb_boot), dim = c(nb_land_time,3,nb_boot))
  colnames(matrixstat) <- c("Cases (s,s+t)","Controls (s,s+t)","Censored (s,s+t)")
  rownames(matrixstat) <- (paste0("s=",land_time))
  
  AUC <- array(rep(NA,nb_land_time*nb_dyn_pred*nb_boot), 
               dim = c(nb_land_time,nb_dyn_pred,nb_boot))
  colnames(AUC) <- colnames(tab[5:ncol(tab)])
  rownames(AUC) <- paste0("s=",land_time)
  
  ref <- AUC_ref(tab,horizon)
  ref_ind <- which(colnames(AUC)==ref)
  
  AUC_se <- array(rep(NA,nb_land_time*nb_dyn_pred*nb_boot), 
                  dim = c(nb_land_time,nb_dyn_pred,nb_boot))
  colnames(AUC_se) <- colnames(tab[5:ncol(tab)])
  rownames(AUC_se) <- paste0("s=",land_time)
  
  matiidAUC <- array(rep(NA,nb_land_time*n*nb_dyn_pred*nb_boot), 
                     dim = c(nb_land_time,n,nb_dyn_pred,nb_boot))
  rownames(matiidAUC) <- (paste0("s=",land_time))
  
  vec_sum_chi2 <- c()
  vec_sum_gamma <- c()
  
  
  ##Global test
  
  for(b in 1:nb_boot){
    
    print(paste("Bootstrap",b))
    
    set.seed(b)
    
    boot <- sample(unique(tab[,1]),nb_ind_boot,replace = T)
    boot_tab <- NULL
    for(i in 1:length(boot)){
      boot_tab <- rbind(boot_tab,tab[which(tab[,1] == boot[i]),])
    }
    
    mat_delta_norm <- matrix(NA, nrow = nb_land_time, ncol = nb_dyn_pred-1)
    colnames(mat_delta_norm) <- paste0("AUC_",colnames(AUC)[-ref_ind],"_",ref)
    rownames(mat_delta_norm) <- paste0("s=",land_time)
    
    vec_sum_mark <- matrix(NA, nrow = nb_land_time, ncol = 1)
    colnames(vec_sum_mark) <- c("sum differences between markers")
    rownames(vec_sum_mark) <- paste0("s=",land_time)
    
    #AUC computation at each landmark time
    for(t in 1:nb_land_time){
      
      s <- land_time[t]
      #Landmark time database
      boot_tab_lan <- boot_tab[which(boot_tab[,2] > s & boot_tab[,4] == s),]
      #Time-to-event vector
      T_s <- boot_tab_lan[,2] - s 
      #Event vector
      boot_tab_lan$delta_s <- 0
      boot_tab_lan$delta_s[which(boot_tab_lan[,2]>s & boot_tab_lan[,2]<=(s+t) & 
                                   boot_tab_lan[,3]==1)] <- 1
      delta_s <- boot_tab_lan$delta_s
      #Predictions table
      prediction <- matrix(NA, nrow = length(delta_s), ncol = nb_dyn_pred)
      colnames(prediction) <- paste0("predictions_",colnames(AUC),"_s")
      for(m in 5:(5+(nb_dyn_pred-1))){
        prediction[,m-4] <- boot_tab_lan[,m]
      }
      indrisk <- unique(boot_tab_lan[,1])
      
      for(m in 1:nb_dyn_pred){
        
        AUC_timeROC <- NULL
        AUC_timeROC <- timeROC(T = T_s, delta = delta_s, marker = prediction[,m], 
                               cause = 1, weighting="marginal",times=c(horizon),
                               iid=TRUE)
        #AUC estimator
        AUC[t,m,b] <- AUC_timeROC$AUC[2] 
        #AUC iid decomposition 
        matiidAUC[t,,m,b] <- c( rep(0,n-AUC_timeROC$n),
                                AUC_timeROC$inference$mat_iid_rep_1[,2]) 
        #s.e estimator
        AUC_se[t,m,b] <- AUC_timeROC$inference$vect_sd_1[2] 
        
      }
      
      matrixstat[t,,b] <- AUC_timeROC$Stats[2,]
      
      count_m <- 1
      for(m in 1:nb_dyn_pred){
        if(m!=ref_ind){
          sisd <- sd(matiidAUC[t,(n-sum(matrixstat[t,,b])+1):n,ref_ind,b]-
                       matiidAUC[t,(n-sum(matrixstat[t,,b])+1):n,m,b])
          sede <- sisd/sqrt(sum(matrixstat[t,,b]))
          mat_delta_norm[t,count_m] <- ((AUC[t,m,b]-AUC[t,ref_ind,b])/sede)**2
          count_m <- count_m+1
        }
      }
      
      vec_sum_mark[t] <- sum(mat_delta_norm[t,])
    }
    
    #One column = s chi2 / one line = one landmark time
    vec_sum_chi2 <- cbind(vec_sum_chi2,vec_sum_mark)  
    vec_sum_gamma <- c(vec_sum_gamma,sum(vec_sum_mark))
    
  }
  
  indNA <- which(is.na(vec_sum_gamma))
  if(length(indNA)!=0){
    sum_chi2 <- vec_sum_chi2[,-indNA]
    sum_gamma <- vec_sum_gamma[-indNA]
  }else{
    sum_chi2 <- vec_sum_chi2
    sum_gamma <- vec_sum_gamma
  }
  
  
  rho <- 0
  for(M1 in 1:nb_land_time){
    for(M2 in 1:nb_land_time){
      if(M1 != M2){
        rho <- rho + cor(sum_chi2[M1,],sum_chi2[M2,])
      }
    }
  }
  
  z <- 2*(1+((2*(nb_dyn_pred-1)*rho)/(nb_land_time*(nb_dyn_pred-1))))
  
  
  ##Post-hoc tests
  if(length(indNA)!=0){
    matiidAUC_withoutNA <- matiidAUC[,,,-indNA]
    matrixstat_withoutNA <- matrixstat[,,-indNA]
    AUC_withoutNA <- AUC[,,-indNA]
  }else{
    matiidAUC_withoutNA <- matiidAUC
    matrixstat_withoutNA <- matrixstat
    AUC_withoutNA <- AUC
  }
  
  nb_pairwise_comp <- choose(nb_dyn_pred,2)
  nb_simu <- length(sum_gamma)
  mat_gamma <- array(rep(NA,nb_simu*nb_pairwise_comp), dim = c(nb_simu,nb_pairwise_comp))
  mat_chi2 <- array(rep(NA,nb_land_time*nb_pairwise_comp*nb_simu), 
                    dim = c(nb_land_time,nb_pairwise_comp,nb_simu))
  
  for(b in 1:nb_simu){
    c <- 0
    for(M1 in 1:(nb_dyn_pred-1)){
      for(M2 in (M1+1):nb_dyn_pred){
        c <- c+1
        for(t in 1:nb_land_time){
          sisd <- sd(matiidAUC_withoutNA[t,(n-sum(matrixstat[t,,b])+1):n,M1,b]-
                       matiidAUC_withoutNA[t,(n-sum(matrixstat[t,,b])+1):n,M2,b])
          if(sisd==0){
            sisd <- 0.000000000000000000001
          }
          sede <- sisd/sqrt(sum(matrixstat_withoutNA[t,,b]))
          Deltanorm <- ((AUC_withoutNA[t,M1,b]-AUC_withoutNA[t,M2,b])/sede)**2
          mat_chi2[t,c,b] <- Deltanorm
        }
        mat_gamma[b,c] <- sum(mat_chi2[,c,b])
      }
    }
  }
  
  rho <- rep(0,nb_pairwise_comp)
  for(comp in 1:nb_pairwise_comp){
    for(s1 in 1:nb_land_time){
      for(s2 in 1:nb_land_time){
        if(s1 != s2){
          rho[comp] <- rho[comp]+cor(mat_chi2[s1,comp,],mat_chi2[s2,comp,])
        }
      }
    }
  }
  
  z_pair <- 2*(1+((2*rho)/(nb_land_time)))
  
  cat("\n")
  
  return(list(global_z = z, pairwise_z = z_pair))
  
}


####################################################
####################################################
##                                                ##
##              Comparison procedure              ##
##                                                ##
####################################################
####################################################

## This function applies the comparison procedure (global comparison, then 
## post-hoc if necessary).

Test_comp <- function(tab,horizon,nb_boot,nb_ind_boot){
  
  nb_dyn_pred <- ncol(tab[,5:ncol(tab)])
  n <- length(unique(tab[,1]))
  land_time <- unique(tab[,4])
  nb_land_time <- length(unique(tab[,4]))
  
  AUC_tab <- AUC_comp(tab,horizon)
  
  ref_marker <- AUC_ref(tab,horizon)
  ref_ind <- which(colnames(AUC_tab$AUC)==ref_marker)
  
  z_para <- z_gammma(tab,horizon,nb_boot,nb_ind_boot)
  
  
  ##Global
  vec_sum_chi2 <- c()
  vec_sum_gamma <- c()
  
  mat_delta_norm <- matrix(NA,nrow = nb_land_time, ncol = nb_dyn_pred-1)
  colnames(mat_delta_norm) <- paste0("AUC_",colnames(AUC_tab$AUC)[-ref_ind],"_",ref_marker)
  rownames(mat_delta_norm) <- paste0("s=",land_time)
  
  vec_sum_mark <- matrix(NA, nrow = nb_land_time, ncol = 1)
  colnames(vec_sum_mark) <- c("sum differences between markers")
  rownames(vec_sum_mark) <- paste0("s=",land_time)
  
  for(t in 1:nb_land_time){
    s <- land_time[t]
    count_m <- 1
    for(m in 1:nb_dyn_pred){
      if(m!=ref_ind){
        sisd <- sd(AUC_tab$mat_iid[t,(n-sum(AUC_tab$stats[t,])+1):n,ref_ind]-
                     AUC_tab$mat_iid[t,(n-sum(AUC_tab$stats[t,])+1):n,m])
        sede <- sisd/sqrt(sum(AUC_tab$stats[t,]))
        mat_delta_norm[t,count_m] <- ((AUC_tab$AUC[t,m]-AUC_tab$AUC[t,ref_ind])/sede)**2
        count_m <- count_m+1
      }
    }
    vec_sum_mark[t] <- sum(mat_delta_norm[t,])
  }
  
  #One column = s chi2 / one line = one landmark time
  vec_sum_chi2 <- cbind(vec_sum_chi2,vec_sum_mark)  
  vec_sum_gamma <- c(vec_sum_gamma,sum(vec_sum_mark))
  
  global_pval <- round(1-pgamma(vec_sum_gamma, 
                                shape = ((nb_land_time*(nb_dyn_pred-1))/z_para$global_z), 
                                scale = z_para$global_z), 16)
  
  
  ##Post-hoc tests
  if(global_pval<0.05 & nb_dyn_pred>2){
    
    nb_pairwise_comp <- choose(nb_dyn_pred,2)
    mat_gamma <- array(rep(NA,nb_pairwise_comp), dim = c(1,nb_pairwise_comp))
    mat_chi2 <- array(rep(NA,nb_land_time*nb_pairwise_comp), 
                      dim = c(nb_land_time,nb_pairwise_comp))
    
    c <- 0
    for(M1 in 1:(nb_dyn_pred-1)){
      for(M2 in (M1+1):nb_dyn_pred){
        c <- c+1
        for(t in 1:nb_land_time){
          sisd <- sd(AUC_tab$mat_iid[t,(n-sum(AUC_tab$stats[t,])+1):n,M1]-
                       AUC_tab$mat_iid[t,(n-sum(AUC_tab$stats[t,])+1):n,M2])
          if(sisd==0){
            sisd <- 0.000000000000000000001
          }
          sede <- sisd/sqrt(sum(AUC_tab$stats[t,]))
          Deltanorm <- ((AUC_tab$AUC[t,M1]-AUC_tab$AUC[t,M2])/sede)**2
          mat_chi2[t,c] <- Deltanorm
        }
        mat_gamma[,c] <- sum(mat_chi2[,c])
      }
    }
    
    ## Naïve p-values
    naive_pval <- matrix(NA, nrow = 1, ncol = nb_pairwise_comp)
    colnames(naive_pval) <- rep(NA, nb_pairwise_comp)
    c <- 0
    for(M1 in 1:(nb_dyn_pred-1)){
      for(M2 in (M1+1):nb_dyn_pred){
        c <- c+1
        colnames(naive_pval)[c] <- paste0(colnames(AUC_tab$AUC)[M1],"_",
                                          colnames(AUC_tab$AUC)[M2])
      }
    }
    for(j in 1:nb_pairwise_comp){
      naive_pval[1,j] <- 1-pgamma(mat_gamma[1,j], 
                                  shape = ((nb_land_time*(2-1))/z_para$pairwise_z[j]), 
                                  scale = z_para$pairwise_z[j])
    }
    
    ## Shaffer p-values
    mat <- diag(NA,nb_dyn_pred)
    index <- 1
    for(i in 1:(nb_dyn_pred-1)){
      cpt <- length(c((i+1):nb_dyn_pred))
      mat[(i+1):nb_dyn_pred,i] <- naive_pval[index:(index+cpt-1)]
      mat[i,(i+1):nb_dyn_pred] <- mat[(i+1):nb_dyn_pred,i]
      index <- index+cpt
    }
    mat_Shaffer <- adjustShaffer(mat)
    Shaffer_pval <- NULL
    for(i in 1:(nb_dyn_pred-1)){
      Shaffer_pval <- c(Shaffer_pval,mat_Shaffer[(i+1):nb_dyn_pred,i])
    }
    Shaffer_pval <- as.data.frame(t(Shaffer_pval), row.names = "")
    colnames(Shaffer_pval) <- colnames(naive_pval)
    
    tabres = as.data.frame(cbind("Reference" = ref_marker,
                                 "p-val" = global_pval), row.names = "")
    
    return(list("Global test" = tabres,
                #"Pairwise naive p-values" = naive_pval,
                "Pairwise Shaffer p-values" = Shaffer_pval))
    
  }else{
    
    tabres = as.data.frame(cbind("Reference" = ref_marker,
                                 "p-val" = global_pval), row.names = "")
    return("Global test" = tabres)
    
  }
  
}


################################################
################################################
##                                            ##
##              Dynamic AUC plot              ##
##                                            ##
################################################
################################################

## This function plots the different dynamic AUCs trajectories according to the 
## different biomarkers and specifies the number of subjects still at risk.

plot_AUC_dyn <- function(tab,horizon){
  
  nb_dyn_pred <- ncol(tab[,5:ncol(tab)])
  n <- length(unique(tab[,1]))
  land_time <- unique(tab[,4])
  nb_land_time <- length(unique(tab[,4]))
  
  AUC_tab <- AUC_comp(tab,horizon)
  
  prediction <- c()
  AUC <- c()
  for(i in 1:nb_dyn_pred){
    prediction <- c(prediction, rep(colnames(AUC_tab$AUC)[i],nb_land_time))
    AUC <- c(AUC, AUC_tab$AUC[,i])
  }
  tab_plot <- as.data.frame(cbind(prediction,AUC,land_time))
  tab_plot$prediction <- as.factor(tab_plot$prediction)
  tab_plot$AUC <- as.numeric(tab_plot$AUC)
  tab_plot$land_time <- as.numeric(tab_plot$land_time)
  
  plot1 <- ggplot(tab_plot, 
                  aes(x = land_time, y = AUC, group = prediction, color=prediction)) +
    geom_line(aes(linetype=prediction, size=prediction)) +
    scale_size_manual(values= rep(c(0.5,1),nb_dyn_pred)[1:nb_dyn_pred]) +
    scale_color_grey(start=0.6, end=0) +
    scale_y_continuous(breaks=seq(0,1,0.1),limits=c(0,1)) +
    theme_classic() + 
    theme(plot.title = element_text(size = 14), 
          legend.title = element_blank(), legend.position = "top") +
    labs(x = "Landmark time s (years)", y = paste0("AUC(s,",horizon,")"))
  
  surv <- do.call(survfit,
                  list(formula = Surv(tab[which(tab[,4]==land_time[1]),2], 
                                      tab[which(tab[,4]==land_time[1]),3]) ~ 1, 
                       data = tab[which(tab[,4]==land_time[1]),]))
  
  plot2 <- ggsurvplot(surv, xlim=c(0,land_time[nb_land_time]),
                      data = tab[which(tab[,4]==land_time[1]),], conf.int = FALSE,                      
                      risk.table = TRUE, risk.table.height = 0.3, ggtheme = theme_classic(),                 
                      censor=FALSE, break.time.by=((land_time[nb_land_time] - land_time[1])/5),
                      risk.table.fontsize = 3.2, risk.table.y.text.fontsize=1, legend.labs = c(""), 
                      tables.theme = theme_survminer(font.main = 11,font.tickslab=10))
  
  fig <- cowplot::plot_grid(
    plot1, plot2$table + theme_cleantable(), nrow = 2, rel_heights = c(10, 1), 
    align = "v", axis = "b")
  
  return(fig)
  
}
