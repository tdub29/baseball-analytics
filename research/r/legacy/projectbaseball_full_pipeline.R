library(baseballr)
library(dplyr)

data_dir <- "data"
raw_dir <- file.path(data_dir, "raw")
interim_dir <- file.path(data_dir, "interim")
processed_dir <- file.path(data_dir, "processed")
metrics_dir <- file.path(data_dir, "metrics")

currentyearcreating<- 2015
endyear <-2019



currentyearcreating <-currentyearcreating +1
#create opening day df
mlb_seasons_all(
  sport_id = 1,
  division_id = NULL,
  league_id = NULL,
  with_game_type_dates = TRUE
)->opening
select(opening, season_id,regular_season_start_date,regular_season_end_date)->opening
filter(opening, season_id == currentyearcreating) ->openingday
openingday$regular_season_start_date ->day1
endofseason <- openingday$regular_season_end_date


#loop to create game result df
odf <- data.frame()


while(day1 != endofseason){
  f <- mlb_game_pks(day1)
  odf <- rbind(odf, f, fill = TRUE)
  day1 <- as.character(as.Date(day1) + 1)
}
duplicate_rows <- duplicated(odf$game_pk)
# Subset the data frame to keep only the rows where game_pk is not a duplicate
odf <- odf[!duplicate_rows, ]
#rename cols
odf <- rename(odf, ATeam = teams.away.team.name)
odf <- rename(odf, HTeam = teams.home.team.name)

filter(odf, !is.na(odf$game_pk))->odf
arrange(odf, officialDate) ->odf



bref_daily_batter(day1,dayf)

df <- data.frame()
#loop to create batter df
df <- data.frame()


select(odf, officialDate)->dates
distinct(dates)->dates
arrange(dates, (officialDate))->dates

openingday$regular_season_start_date ->day1
dayf<- as.character(as.Date(day1) + 15)
for(i in dates$officialDate){
out <- bref_daily_batter(day1,dayf)
out$Team <- sub("\\,.*", "", out$Team)
out$Team <- paste(out$Team,substr(out$Level, 5,6))
out$Team[out$Team == 'Colorado AL'] <- 'Colorado Rockies'
out$Team[out$Team == 'Colorado NL'] <- 'Colorado Rockies'
out$Team[out$Team == 'Atlanta NL'] <- 'Atlanta Braves'
out$Team[out$Team == 'Atlanta AL'] <- 'Atlanta Braves'
out$Team[out$Team == 'Miami NL'] <- 'Miami Marlins'
out$Team[out$Team == 'Miami AL'] <- 'Miami Marlins'
out$Team[out$Team == 'Arizona NL'] <- 'Arizona Diamondbacks'
out$Team[out$Team == 'Arizona AL'] <- 'Arizona Diamondbacks'
out$Team[out$Team == 'San Diego NL'] <- 'San Diego Padres'
out$Team[out$Team == 'San Diego NL'] <- 'San Diego Padres'
out$Team[out$Team == 'Philadelphia NL'] <- 'Philadelphia Phillies'
out$Team[out$Team == 'Philadelphia AL'] <- 'Philadelphia Phillies'
out$Team[out$Team == 'Baltimore AL'] <- 'Baltimore Orioles'
out$Team[out$Team == 'Boston AL'] <- 'Boston Red Sox'
out$Team[out$Team == 'Chicago AL'] <- 'Chicago White Sox'
out$Team[out$Team == 'Chicago NL'] <- 'Chicago Cubs'
out$Team[out$Team == 'Cincinnati NL'] <- 'Cincinnati Reds'
out$Team[out$Team == 'Cleveland AL'] <- 'Cleveland Indians'
out$Team[out$Team == 'Detroit AL'] <- 'Detroit Tigers'
out$Team[out$Team == 'Houston AL'] <- 'Houston Astros'
out$Team[out$Team == 'Kansas City AL'] <- 'Kansas City Royals'
out$Team[out$Team == 'Los Angeles NL'] <- 'Los Angeles Dodgers'
out$Team[out$Team == 'Los Angeles AL'] <- 'Los Angeles Angels'
out$Team[out$Team == 'Milwaukee NL'] <- 'Milwaukee Brewers'
out$Team[out$Team == 'Minnesota AL'] <- 'Minnesota Twins'
out$Team[out$Team == 'New York NL'] <- 'New York Mets'
out$Team[out$Team == 'New York AL'] <- 'New York Yankees'
out$Team[out$Team == 'Oakland AL'] <- 'Oakland Athletics'
out$Team[out$Team == 'Pittsburgh NL'] <- 'Pittsburgh Pirates'
out$Team[out$Team == 'San Francisco NL'] <- 'San Francisco Giants'
out$Team[out$Team == 'Seattle AL'] <- 'Seattle Mariners'
out$Team[out$Team == 'St. Louis NL'] <- 'St. Louis Cardinals'
out$Team[out$Team == 'Tampa Bay AL'] <- 'Tampa Bay Rays'
out$Team[out$Team == 'Texas AL'] <- 'Texas Rangers'
out$Team[out$Team == 'Toronto AL'] <- 'Toronto Blue Jays'
out$Team[out$Team == 'Washington NL'] <- 'Washington Nationals'
output <- aggregate(out[8:26], by = list(as.factor(out$Team)), sum)
output <- mutate(output, avg = H/AB, obp = (H + BB + HBP)/(AB+BB+HBP+SF), slg = (X1B + 2*X2B + 3*X3B + HR*4)/AB, OPS = obp + slg, wOBA = (0.687*uBB + 0.718*HBP + 0.881*X1B + 1.256*X2B + 1.594*X3B + 2.065*HR) / (AB + BB - IBB + SF + HBP), Pdate = as.Date(dayf) + 1)
output <- rename(output, Team = "Group.1")
df = rbind(df, output)
day1 <- as.character(as.Date(day1) + 1)
dayf <- as.character(as.Date(dayf) + 1)


#remove any teams that dont exist
df <- filter(df, df$PA > 100)





#loop to create pitcher dfs
spdf<- data.frame()
rpdf <- data.frame()




openingday$regular_season_start_date ->day1
dayf <- as.character(as.Date(day1)+15)
while(dayf != endofseason){
  as.Date(dayf)-as.Date(day1) -> dayrange
  as.numeric(dayrange)->dayrange
  out <- bref_daily_pitcher(day1,dayf)
  out$Team <- sub("\\,.*", "", out$Team)
  out$Team <- paste(out$Team,substr(out$Level, 5,6))
  out$Team[out$Team == 'Colorado AL'] <- 'Colorado Rockies' 
  out$Team[out$Team == 'Colorado NL'] <- 'Colorado Rockies'
  out$Team[out$Team == 'Atlanta NL'] <- 'Atlanta Braves'
  out$Team[out$Team == 'Atlanta AL'] <- 'Atlanta Braves'
  out$Team[out$Team == 'Miami NL'] <- 'Miami Marlins'
  out$Team[out$Team == 'Miami AL'] <- 'Miami Marlins'
  out$Team[out$Team == 'Arizona NL'] <- 'Arizona Diamondbacks'
  out$Team[out$Team == 'Arizona AL'] <- 'Arizona Diamondbacks'
  out$Team[out$Team == 'San Diego NL'] <- 'San Diego Padres'
  out$Team[out$Team == 'San Diego AL'] <- 'San Diego Padres'
  out$Team[out$Team == 'Philadelphia NL'] <- 'Philadelphia Phillies'
  out$Team[out$Team == 'Philadelphia AL'] <- 'Philadelphia Phillies'
  out$Team[out$Team == 'Baltimore AL'] <- 'Baltimore Orioles'
  out$Team[out$Team == 'Boston AL'] <- 'Boston Red Sox'
  out$Team[out$Team == 'Chicago AL'] <- 'Chicago White Sox'
  out$Team[out$Team == 'Chicago NL'] <- 'Chicago Cubs'
  out$Team[out$Team == 'Cincinnati NL'] <- 'Cincinnati Reds'
  out$Team[out$Team == 'Cleveland AL'] <- 'Cleveland Indians'
  out$Team[out$Team == 'Detroit AL'] <- 'Detroit Tigers'
  out$Team[out$Team == 'Houston AL'] <- 'Houston Astros'
  out$Team[out$Team == 'Kansas City AL'] <- 'Kansas City Royals'
  out$Team[out$Team == 'Los Angeles NL'] <- 'Los Angeles Dodgers'
  out$Team[out$Team == 'Los Angeles AL'] <- 'Los Angeles Angels'
  out$Team[out$Team == 'Milwaukee NL'] <- 'Milwaukee Brewers'
  out$Team[out$Team == 'Minnesota AL'] <- 'Minnesota Twins'
  out$Team[out$Team == 'New York NL'] <- 'New York Mets'
  out$Team[out$Team == 'New York AL'] <- 'New York Yankees'
  out$Team[out$Team == 'Oakland AL'] <- 'Oakland Athletics'
  out$Team[out$Team == 'Pittsburgh NL'] <- 'Pittsburgh Pirates'
  out$Team[out$Team == 'San Francisco NL'] <- 'San Francisco Giants'
  out$Team[out$Team == 'Seattle AL'] <- 'Seattle Mariners'
  out$Team[out$Team == 'St. Louis NL'] <- 'St. Louis Cardinals'
  out$Team[out$Team == 'Tampa Bay AL'] <- 'Tampa Bay Rays'
  out$Team[out$Team == 'Texas AL'] <- 'Texas Rangers'
  out$Team[out$Team == 'Toronto AL'] <- 'Toronto Blue Jays'
  out$Team[out$Team == 'Washington NL'] <- 'Washington Nationals'
  out$Team[out$Team == 'Cincinnati AL'] <- 'Cincinnati Reds'
  out$Team[out$Team == 'Milwaukee NL'] <- 'Milwaukee Brewers'
  out$Team[out$Team == 'Pittsburgh AL'] <- 'Pittsburgh Pirates'
  poutput <- mutate(out,fip = ((13*HR)+(3*(BB+HBP))-(2*SO))/IP + 3.134 ,Pdate = as.Date(dayf) + 1)
  poutput <- mutate(poutput, position = ifelse(poutput$GS<1, "RP", "SP"))
  SP <- filter(poutput, position == "SP")
  spdf = rbind(spdf, SP)
  RP1 <- filter(poutput, position == "RP")
  RP <- aggregate(RP1[7:33], by = list(as.factor(RP1$Team)), sum)
  RP <- select(RP, -(ERA))
  RP <- rename(RP, Team = "Group.1")
  RP <- mutate(RP, fip = ((13*HR)+(3*(BB+HBP))-(2*SO))/IP + 3.134 , era = 9 * (ER/IP),whip = (BB + HBP + H)/IP,kperc = (SO/AB), Pdate = as.Date(dayf) + 1 )
  rpdf = rbind(rpdf, RP)
  day1 <- ifelse(dayrange >= 30,as.character(as.Date(day1) + 1),day1)
  dayf <- as.character(as.Date(dayf) + 1)

spdf ->spdf2017
  rename(rpdf,  "RPteam"="Team" )->rpdf
  



#Loop to create starting pitcher df by game
startdf <- data.frame()
for(i in odf$game_pk){
  starter <- mlb_probables(i)
  startdf <- rbind(startdf, starter)}


library(sqldf)
sqldf()






#merge batter data and game results
rename(odf, Date = officialDate)->odf
odf$Date <- as.Date(odf$Date)


#home batter data join
q1 <- "SELECT *
FROM odf
LEFT JOIN df
ON df.Team = odf.HTeam AND df.Pdate = odf.Date;"
sqldf(q1) -> y
#away batter data join
q2 <- "SELECT *
FROM y
LEFT JOIN df
ON df.Team = y.ATeam AND df.Pdate = y.Date;"
sqldf(q2) -> X
paste("a", colnames(X[93:118]), sep = "" ) -> i
colnames(X)[93:118] <- c(i)
select(X, -(aTeam)) -> X

paste("rp", colnames(rpdf[1:32]), sep = "" ) -> u
colnames(rpdf)[1:32] <- c(u)
#home relief pitcher data join
q4 <- "SELECT *
FROM X
LEFT JOIN rpdf
ON rpdf.RPteam = X.HTeam AND rpdf.RPPdate = X.Date;"
sqldf(q4) -> rpadd

rpadd -> NEW
paste("a", colnames(rpdf[1:32]), sep = "" ) -> u
colnames(rpdf)[1:32] <- c(u)
#remove unnecessary repeated away team name


# home starter join
q5 <- "SELECT NEW.*, startdf.fullName
FROM NEW
LEFT JOIN startdf
ON startdf.team = NEW.HTeam AND startdf.game_pk = NEW.game_pk;"
X <- sqldf(q5)


paste("sp", colnames(spdf[1:49]), sep = "" ) -> u
colnames(spdf)[1:49] <- c(u)
#home starter data join
q7 <- "SELECT *
FROM X
LEFT JOIN spdf
ON spdf.spName = X.fullName AND spdf.spPdate = X.Date;"
rpadd <- sqldf(q7)


#away starter join
q8 <- "SELECT rpadd.*, startdf.fullName
FROM rpadd
LEFT JOIN startdf
ON startdf.team = rpadd.ATeam AND startdf.game_pk = rpadd.game_pk;"
NEW <- sqldf(q8)
colnames(NEW)[150] ="Home Starter"
colnames(NEW)[200] ="AwayStarter"


#away starter data join
q9 <- "SELECT *
FROM NEW
LEFT JOIN spdf
ON spdf.spName = NEW.AwayStarter AND spdf.spPdate = NEW.Date;"
X <- sqldf(q9)
paste("h", colnames(X[151:199]), sep = "" ) -> up
colnames(X)[151:199] <- c(up)

#away reliever data join
q10 <- "SELECT *
FROM X
LEFT JOIN rpdf
ON rpdf.aRPteam = X.ATeam AND rpdf.aRPPdate = X.Date;"
NEW <- sqldf(q10)


paste("a", colnames(NEW[201:249]), sep = "" ) -> as
colnames(NEW)[201:249] <- c(as)


#remove unnecessary columns
select(NEW, -(arpPdate)) -> NEW
select(NEW, -(hrpPdate)) -> NEW
select(NEW, -(dates)) -> NEW
select(odf, -(dates)) -> odf

#rename starting pitcher name cols



X <- X[,-154]

#distinguish away/home cols







#loop through mlbgamepk column using mlb_probables to add starting pitcher


#remove error row
NEW <- filter(NEW, game_pk != 1)



write.csv(baseball, file = file.path(processed_dir, "years_baseball.csv"))
write.csv(baseballcorr, file = file.path(metrics_dir, "baseball_correlations.csv"))
write.csv(df, file = file.path(interim_dir, "team_batting_rolling.csv"))
write.csv(startdf, file = file.path(raw_dir, "mlb_probable_starters.csv"))
write.csv(rpdf, file = file.path(interim_dir, "team_relief_pitching_rolling.csv"))
write.csv(spdf, file = file.path(interim_dir, "team_starting_pitching_rolling.csv"))
write.csv(odf, file = file.path(raw_dir, "mlb_game_schedule.csv"))


gamedata <- read.csv(file.path(raw_dir, "mlb_game_schedule.csv"))
baseball <- read.csv(file.path(processed_dir, "years_baseball.csv"))
battingdata <- read.csv(file.path(interim_dir, "team_batting_rolling.csv"))
starterdata <- read.csv(file.path(interim_dir, "team_starting_pitching_rolling.csv"))
starters <- read.csv(file.path(raw_dir, "mlb_probable_starters.csv"))
relieverdata <- read.csv(file.path(interim_dir, "team_relief_pitching_rolling.csv"))



duplicate_rows <- duplicated(baseball$game_pk)
  # Subset the data frame to keep only the rows where game_pk is not a duplicate
   baseball <- baseball[!duplicate_rows, ]



#remove rows without pitching data
cleaned_data <- subset(baseball, !is.na(baseball[173]))
cleaned_data <- subset(cleaned_data, !is.na(cleaned_data$aspERA.1))

baseball <-cleaned_data

#add pitcher slugging and different expected score metrics created through linear regression

mutate(baseball, rpslg = (rpX1B + (rpX2B * 2) + (rpX3B * 3) + (rpHR * 4)) / rpAB, hspslg = (hspX1B + (hspX2B * 2) + (hspX3B * 3) + (hspHR * 4)) / hspAB)->baseball
mutate(baseball, arpslg = (arpX1B + (arpX2B * 2) + (arpX3B * 3) + (arpHR * 4)) / arpAB, aspslg.1 = (aspX1B.1 + (aspX2B.1 * 2) + (aspX3B.1 * 3) + (aspHR.1 * 4)) / aspAB.1)->baseball


mutate(baseball, awayexscore = (rpslg * rpHR + ((-1 * hspSO_perc)*hspLD * hspslg) * aslg))-> baseball
mutate(baseball, homeexscore = (arpslg * arpHR + ((-1 * aspSO_perc.1)*aspLD.1 * aspslg.1) * slg))-> baseball
baseball$homeexpected_score <- (baseball$arpslg * 10.79940) + (baseball$arpHR * 0.33009) + ((-1 * baseball$aspSO_perc.1) * baseball$aspLD.1 * baseball$aspslg.1 * baseball$slg) - (baseball$arpslg * baseball$arpHR * 0.74867)
baseball$awayexpected_score <- (baseball$rpslg * 10.79940) + (baseball$rpHR * 0.33009) + ((-1 * baseball$hspSO_perc) * baseball$hspLD * baseball$hspslg * baseball$aslg) - (baseball$rpslg * baseball$rpHR * 0.74867)


#colsneeded for model arpslg,arpHR,aspSO_perc.1,aspLD.1,aspslg.1,slg,rpslg,rpHR,hspSO_perc,hspLD,hspslg,aslg


#select predictive stats and actual scores and create df with home/away removed
select(baseball, teams.away.score, teams.home.score, 67:90, 92:115, 118:147,  248:277, 154:194,204:244) -> sig
sig <- sig[complete.cases(sig[,c(1,2)]),]
select(sig,-(154:156))->sig
 select(sig,-(113:115))->sig
 select(sig,-(53:55),-(83:85))->sig
 asig <- select(sig, 1, 27:50, 51:77,105:142)
 hsig <- select(sig, -1, -(27:50), -(51:77),-(105:142))
 names(hsig) -> names(asig)
 rbind(hsig,asig)->sigg
 colnames(sigg)[25:ncol(sigg)] <- gsub("^.", "", colnames(sigg)[25:ncol(sigg)])
 rename(sigg, score = teams.home.score)->sigg
 
 #replace remaining na values with averages
 for (i in 1:ncol(sigg)){
   sigg[is.na(sigg[,i]), i] <- mean(sigg[,i], na.rm = TRUE)
 }
 #add reliever and starter slugging
 mutate(sigg, rpslg = (rpX1B + (rpX2B * 2) + (rpX3B * 3) + (rpHR * 4)) / rpAB, spslg.1 = (spX1B.1 + (spX2B.1 * 2) + (spX3B.1 * 3) + (spHR.1 * 4)) / spAB.1)->sigg
 
 #remove scientific notation and create df with correlations
 options(scipen = 999)
 data.frame(cor(sigg))->baseballcorr
 
 library(ggplot2)
 library(rsq)
 #add formula used for builing multiple linear regression model no coef
 mutate(sigg, exscore =  (rpslg * rpHR + ((-1 * spSO_perc.1)*spLD.1 * spslg.1) * slg))->sigg
 #add formula used for builing multiple linear regression model w/ coef
 sigg$expected_score <- (sigg$rpslg * 10.79940) + (sigg$rpHR * 0.33009) + ((-1 * sigg$spSO_perc.1) * sigg$spLD.1 * sigg$spslg.1 * sigg$slg) - (sigg$rpslg * sigg$rpHR * 0.74867)
 model <- lm(score ~ expected_score, data = sigg)
highrmodel <- lm(score ~ (rpslg * rpHR + ((-1 * spSO_perc.1)*spLD.1 * spslg.1) * slg), data = sigg)
summary(highrmodel)
summary(model)
rsq(highrmodel)#!!!
coef <- round(coef(model)[2],3)

#different graphs
library(tseries)
library(ggplot2)
highrmodel <- lm(score ~ (rpslg * rpHR + ((-1 * spSO_perc.1)*spLD.1 * spslg.1) * slg), data = sigg)
ggplot(sigg, aes((rpslg * rpHR + ((-1 * spSO_perc.1)*spLD.1 * spslg.1) * slg), score)) +
  geom_point() +
  geom_smooth(method = "lm", se = FALSE) +
  ggtitle(paste("baseball R-squared: ", round(rsq(highrmodel), 3)))

model <- lm(score ~ expected_score, data = sigg)
ggplot(sigg, aes(expected_score, score)) +
  geom_point() +
  geom_smooth(method = "lm", se = FALSE)+
  ggtitle(paste(" Coefficient: ",coef(model)[2]))

model <- lm(score ~ exscore, data = sigg)

ggplot(sigg, aes(exscore, score)) +
  geom_point() +
  geom_smooth(method = "lm", se = FALSE)

#basicthresholdanalysis

bad <- filter(sigg, expected_score < 3.5)
good <- filter(sigg, expected_score > 4.5)

mean(good$score, na.rm = T)
mean(bad$score, na.rm = T)




#add historic scores given exscore and how similar exscores performed as well as number of times such an event occurred and the pvalue associated with the score in those games 
for(x in 1:nrow(baseball)){
  abaseballthreshold <- baseball$awayexscore[x] 
  hbaseballthreshold <- baseball$homeexscore[x] 
  filter(sigg, exscore >= abaseballthreshold*0.95 & exscore <= abaseballthreshold*1.05) -> abaseballthresh#pct >= fpercentreq*0.95 & pct <= fpercentreq*1.05
  filter(sigg, exscore >= hbaseballthreshold*0.95 & exscore <= hbaseballthreshold*1.05) -> hbaseballthresh#pct >= fpercentreq*0.95 & pct <= fpercentreq*1.05
  mean(abaseballthresh$score) -> aoutcome
  mean(hbaseballthresh$score) -> houtcome
  
  baseball$homehistoricalpred[x] <- houtcome
  baseball$awayhistoricalpred[x] <- aoutcome
  baseball$homeoccurences[x]<-nrow(hbaseballthresh)
  baseball$awayoccurences[x]<-nrow(abaseballthresh)
  baseball$hpval[x] <- jarque.bera.test(hbaseballthresh$score)$p.value
  baseball$apval[x] <- jarque.bera.test(abaseballthresh$score)$p.value
  
}
#regress exscore 
#mean_homeexscore <- mean(baseball$homeexscore, na.rm = TRUE)
#outliers <- baseball[baseball$homeexscore > mean_homeexscore + 2.5*sd(baseball$homeexscore, na.rm = TRUE) | baseball$homeexscore < mean_homeexscore - 2.5*sd(baseball$homeexscore, na.rm = TRUE),]
#outliers$homeexscore <- outliers$homeexscore - (outliers$homeexscore - mean_homeexscore)/2
#baseball[baseball$homeexscore > mean_homeexscore + 2.5*sd(baseball$homeexscore, na.rm = TRUE) | baseball$homeexscore < mean_homeexscore - 2*sd(baseball$homeexscore, na.rm = TRUE),] <- outliers


#regress predictions back to mean incases where pvalue is high
mean_homehistoricalpred <- mean(baseball$homehistoricalpred, na.rm = TRUE)
mean_awayhistoricalpred <- mean(baseball$awayhistoricalpred, na.rm = TRUE)

filter(baseball, awayoccurences != 0)->baseball
filter(baseball, homeoccurences != 0)->baseball


for (i in 1:nrow(baseball)) {
  baseball$apval[i] <- ifelse(is.na(baseball$apval[i]), 0.75, baseball$apval[i])
  baseball$hpval[i] <- ifelse(is.na(baseball$hpval[i]), 0.75, baseball$hpval[i])
  
  if (baseball$hpval[i] > 0.05) {
    baseball$homehistoricalpred[i] = baseball$homehistoricalpred[i] - (baseball$homehistoricalpred[i] - mean_homehistoricalpred) * (0.2 +.5*baseball$hpval[i])
  }
  if (baseball$apval[i] > 0.05) {
    baseball$awayhistoricalpred[i] = baseball$awayhistoricalpred[i] - (baseball$awayhistoricalpred[i] - mean_awayhistoricalpred) * (0.2+.5*baseball$apval[i])
  }
}
#create column for historical pointdifference
mutate(baseball, homeadvantage = homehistoricalpred -awayhistoricalpred,awayadvantage = awayhistoricalpred -homehistoricalpred)->baseball
#set NA differences to even
baseball$homeadvantage[is.na(baseball$homeadvantage)] <- 0
baseball$awayadvantage[is.na(baseball$awayadvantage)] <- 0







#create df with score and opponent score w/o home/away along with predicted team score, predicted scored differential and whether that observtion won in order to calc win %
select(baseball,teams.home.score, teams.away.score, homehistoricalpred, awayhistoricalpred,homeadvantage,awayadvantage)->advantageanalysis
mutate(advantageanalysis, hoppscore = teams.away.score, aoppscore = teams.home.score)->advantageanalysis
select(advantageanalysis, 1,3,5,7)->hadv
select(advantageanalysis, 2,4,6,8)->aadv
names(hadv)<- c("score", 'predictedscore','predadv','oppscore')
names(aadv)<- c("score", 'predictedscore','predadv','oppscore')
rbind(aadv,hadv)->advantageanalysis
mutate(advantageanalysis, actualdiff =score-oppscore)->advantageanalysis
advantageanalysis$win <- ifelse(advantageanalysis$actualdiff > 0, 1,0)
na.omit(advantageanalysis)->advantageanalysis


#calculate win percentage given historical difference, creates historical score difference given expected,win percent, pvalue associated with the column representing a win
for(x in 1:nrow(baseball)){
  aadvthreshold <- baseball$awayadvantage[x] 
  hadvthreshold <- baseball$homeadvantage[x] 
  if (hadvthreshold >= 0) {
    filter(advantageanalysis, predadv >= hadvthreshold *0.94 & predadv <= hadvthreshold * 1.06) -> hadvthresh
  } else {
    filter(advantageanalysis, predadv <= hadvthreshold * 0.94 & predadv >= hadvthreshold * 1.06) -> hadvthresh
  }
  if (aadvthreshold >= 0) {
    filter(advantageanalysis, predadv >= aadvthreshold *0.94 & predadv <= aadvthreshold * 1.06) -> aadvthresh
  } else {
    filter(advantageanalysis, predadv <= aadvthreshold * 0.94 & predadv >= aadvthreshold * 1.06) -> aadvthresh
  }
  mean(aadvthresh$actualdiff) -> awayadv
  mean(hadvthresh$actualdiff) -> homeadv
  baseball$homehistoricaldiff[x] <- homeadv
  baseball$awayhistoricaldiff[x] <- awayadv
  baseball$homewinpct[x]<-sum(hadvthresh$win) /nrow(hadvthresh)
  baseball$awaywinpct[x]<-sum(aadvthresh$win) /nrow(aadvthresh)
  baseball$hwinpctpval[x] <- jarque.bera.test(hadvthresh$win)$p.value
  baseball$awinpctpval[x] <- jarque.bera.test(aadvthresh$win)$p.value
  baseball$hobservswinpct[x]<- nrow(hadvthresh)
  baseball$aobservswinpct[x]<- nrow(aadvthresh)
  
  
}

baseball$homewinpct[is.na(baseball$homewinpct)] <- 1 - baseball$awaywinpct[is.na(baseball$homewinpct)]
baseball$awaywinpct[is.na(baseball$awaywinpct)] <- 1 - baseball$homewinpct[is.na(baseball$awaywinpct)]
baseball$hwinpctpval <- ifelse(is.na(baseball$hwinpctpval), baseball$awinpctpval, baseball$hwinpctpval)
baseball$awinpctpval <- ifelse(is.na(baseball$awinpctpval), baseball$hwinpctpval, baseball$awinpctpval)
baseball$hobservswinpct <- ifelse(baseball$hobservswinpct==0, baseball$aobservswinpct, baseball$hobservswinpct)
baseball$aobservswinpct <- ifelse(baseball$aobservswinpct==0, baseball$hobservswinpct, baseball$aobservswinpct)


filter(baseball, aobservswinpct != 0)->baseball
filter(baseball, hobservswinpct != 0)->baseball

#regress projected win % back to the mean in cases where pvalue is high
mean_homewinpct <- mean(baseball$homewinpct, na.rm = TRUE)
mean_awaywinpct <- mean(baseball$awaywinpct, na.rm = TRUE)
baseball<-bbback
for (i in 1:nrow(baseball)) {
  baseball$awinpctpval[i] <- ifelse(is.na(baseball$awinpctpval[i]), 0.75, baseball$awinpctpval[i])
  baseball$hwinpctpval[i] <- ifelse(is.na(baseball$hwinpctpval[i]), 0.75, baseball$hwinpctpval[i])
  
  if (baseball$hwinpctpval[i] > 0.05) {
    baseball$homewinpct[i] = baseball$homewinpct[i] - (baseball$homewinpct[i] - mean_homewinpct) * (0.2 +.5*baseball$hwinpctpval[i])
  }
  if (baseball$awinpctpval[i] > 0.05) {
    baseball$awaywinpct[i] = baseball$awaywinpct[i] - (baseball$awaywinpct[i] - mean_awaywinpct) * (0.2+.5*baseball$awinpctpval[i])
  }
}



select(baseball, awaywinpct, homewinpct ,teams.home.isWinner, teams.away.isWinner)->winners
select(winners, 1,4)->awiner
select(winners,2,3)->hwiner
names(awiner)<- c('winpct', 'win')
names(hwiner)<- c('winpct', 'win')
rbind(hwiner,awiner)->winner
filter(winner, winpct > .55)->wina
sum(wina$win, na.rm = T)/nrow(wina)

select(baseball, awayhistoricalpred, homehistoricalpred ,teams.home.score, teams.away.score)->winners
select(winners, 1,4)->awiner
select(winners,2,3)->hwiner
names(awiner)<- c('pred', 'score')
names(hwiner)<- c('pred', 'score')
rbind(hwiner,awiner)->scarprd
filter(winner, winpct > .55)->scrprd
sum(wina$win, na.rm = T)/nrow(wina)

select(baseball, awayexpected_score, homeexpected_score ,teams.home.score, teams.away.score)->winners
select(winners, 1,4)->awiner
select(winners,2,3)->hwiner
names(awiner)<- c('exp', 'score')
names(hwiner)<- c('exp', 'score')
rbind(hwiner,awiner)->scar
filter(winner, winpct > .55)->scrprd
sum(wina$win, na.rm = T)/nrow(wina)




model <- lm(score ~ pred, data = scarprd)
summary(model)
ggplot(scarprd, aes(pred, score)) +
  geom_point() +
  geom_smooth(method = "lm", se = FALSE) +
  ggtitle(paste(" Coefficient: ",coef(model)[2]))
ggplot(baseball, aes(wOBA, teams.home.score)) + geom_point() + geom_smooth(span = .1)


model <- lm(score ~ exp, data = scar)
summary(model)
ggplot(scar, aes(exp, score)) +
  geom_point() +
  geom_smooth(method = "lm", se = FALSE) +
  ggtitle(paste(" Coefficient: ",coef(model)[2]))
ggplot(baseball, aes(wOBA, teams.home.score)) + geom_point() + geom_smooth(span = .1)

