library(data.table)
library(ggplot2)
library(viridis)

rm(list=ls())
data <- melt(rbindlist(lapply(list.files(pattern = "ListUtil_OMP_.*\\.csv"), function(file) {
  size <- as.integer(gsub("ListUtil_OMP_([[:digit:]]+).csv", "\\1", file))
  dt <- fread(file)
  dt[, Size := size]
})), id.vars = "Size")

setnames(data, c("variable", "value"), c("variable", "Time"))

## split the value of the Function column, using the "_" to separate the new columns
data[, c("Code", "Function", "space", "Nthreads") := tstrsplit(variable, "_", fixed = TRUE)]
data$Size <- factor(data$Size)
data[Code == "OMP", Code := paste("OMP", Nthreads, sep = "_")]
data$Code <- factor(data$Code, levels = c("ForLoop", "ListUtil", "StC", paste(
  "OMP", c("01", "02", "03", "04", "05", "06", "07", "08"), sep = "_"
)))

ggplot(data, aes(x = Code, y = Time)) + geom_boxplot() +
  scale_y_log10(breaks = 10 ^ (-6:-1))  + facet_grid(Size ~ Function) + theme_bw() +
  ylab("Time (sec)") + xlab("Code") + coord_flip()
ggsave(
  "ListUtil_OMP.png",
  width = 6,
  height = 10,
  units = "in",
  dpi = 600
)

ggplot(data[is.element(Size, c("100", "10000", "1000000")), ], aes(x = Code, y = Time)) + geom_boxplot() +
  scale_y_log10(breaks = 10 ^ (-6:-1))  + facet_grid(Size ~ Function) + theme_bw() +
  ylab("Time (sec)") + xlab("Code") + coord_flip()
ggsave(
  "ListUtil_OMP_limited.png",
  width = 6,
  height = 8,
  units = "in",
  dpi = 600
)



ggplot(data[is.element(Size, c("100", "10000", "1000000")), ], aes(x = Code, y = Time, color =
                                                                     Size)) + geom_boxplot() +
  scale_y_log10(breaks = 10 ^ (-6:-1))  + facet_grid(Function ~ .) + theme_bw() +
  ylab("Time (sec)") + xlab("Code") + scale_color_viridis(discrete = TRUE)
ggsave(
  "ListUtil_OMP_limited_color.png",
  width = 10,
  height = 6,
  units = "in",
  dpi = 600
)
## scale the time for all the data to that of the ForLoop with the same Size
data_scale <- copy(data)
data_scale <- data_scale[, Time := Time / Time[Code == "ForLoop"], by = .(Size, Function)]

ggplot(data_scale[is.element(Size, c("100", "10000", "1000000")) &
                    Code != "ForLoop", ], aes(x = Code, y = Time, color = Size)) + geom_boxplot() +
  scale_y_log10()  + facet_grid(Function ~ .) + theme_bw() +
  ylab("Timing Ratio (vs ForLoop of the same size)") + xlab("Code") + scale_color_viridis(discrete = TRUE)
ggsave(
  "ListUtil_OMP_ratio_limited_color.png",
  width = 10,
  height = 6,
  units = "in",
  dpi = 600
)


## scale the data to the Time with the same Code at Size = 100
data_scale_size <- copy(data)
data_scale_size <- data_scale_size[, Time := Time / Time[Size == "100" ], by = .(Function, Code)]
ggplot(data_scale_size[is.element(Size, c( "10000", "1000000")) , ], aes(x = Code, y = Time, color = Size)) + geom_boxplot() +
  scale_y_log10()  + facet_grid(Function ~ .) + theme_bw() +
  ylab("Timing Ratio (vs Code of size = 100)") + xlab("Code") + scale_color_viridis(discrete = TRUE)
