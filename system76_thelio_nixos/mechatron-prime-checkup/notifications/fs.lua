-- Linux-only durable filesystem adapter. All route components reject symlinks.
local ffi=require("ffi")
local bit=require("bit")
ffi.cdef[[
int open(const char *, int, ...); int openat(int, const char *, int, ...);
int close(int); long read(int, void *, unsigned long); long write(int, const void *, unsigned long);
int fsync(int); int mkdirat(int,const char *,unsigned int); int unlinkat(int,const char *,int);
int renameat(int,const char *,int,const char *); int linkat(int,const char *,int,const char *,int);
int flock(int,int); unsigned int geteuid(void);
int fchmod(int,unsigned int);
struct notification_timestamp { int64_t sec; uint32_t nsec; int32_t reserved; };
struct notification_statx { uint32_t mask, blksize; uint64_t attributes;
 uint32_t nlink,uid,gid; uint16_t mode,spare; uint64_t ino,size,blocks,attributes_mask;
 struct notification_timestamp atime,btime,ctime,mtime;
 uint32_t rdev_major,rdev_minor,dev_major,dev_minor; char remaining[112]; };
int statx(int,const char *,int,unsigned int,struct notification_statx *);
struct notification_dirent { uint64_t ino; int64_t off; unsigned short reclen; unsigned char type; char name[256]; };
void *fdopendir(int); struct notification_dirent *readdir(void *); int closedir(void *); int dup(int);
]]
assert(ffi.os=="Linux","CI notification adapter requires Linux")
local C=ffi.C
local M={}
local RDONLY,WRONLY,CREAT,EXCL,DIRECTORY,NOFOLLOW,CLOEXEC,NONBLOCK=0,1,64,128,65536,131072,524288,2048
if ffi.arch=="arm64" then DIRECTORY,NOFOLLOW=16384,32768 end
local counter=0
local function check(value,message) assert(value>=0,message.." (errno "..ffi.errno()..")"); return value end
local function info(fd)
	local s=ffi.new("struct notification_statx[1]")
	check(C.statx(fd,"",4096,0x7ff,s),"statx")
	return s[0]
end
local function inode(fd)
	local s=info(fd); return tostring(s.dev_major)..":"..tostring(s.dev_minor)..":"..tostring(s.ino)
end
local function withfd(fd,fn)
	local ok,a=pcall(fn,fd); C.close(fd)
	if not ok then error(a,0) end
	return a
end
local function directory(path)
	assert(type(path)=="string" and path:sub(1,1)=="/" and not path:find("%z"),"absolute canonical path required")
	local fd=check(C.open("/",bit.bor(RDONLY,DIRECTORY,CLOEXEC)),"open root")
	local ids={inode(fd)}
	for part in path:gmatch("[^/]+") do
		if part=="." or part==".." then C.close(fd); error("noncanonical path") end
		local nextfd=C.openat(fd,part,bit.bor(RDONLY,DIRECTORY,NOFOLLOW,CLOEXEC))
		C.close(fd); check(nextfd,"unsafe or inaccessible directory")
		fd=nextfd; ids[#ids+1]=inode(fd)
	end
	return fd,table.concat(ids,"/")
end
local function parent(path)
	local dir,name=path:match("^(.*)/([^/]+)$")
	assert(dir and name~="." and name~="..","invalid file path")
	return directory(dir=="" and "/" or dir),name
end
local function contents(fd,limit)
	assert(bit.band(info(fd).mode,61440)==32768,"not a regular file")
	local chunks,total={},0; local buffer=ffi.new("char[4096]")
	while true do
		local n=check(C.read(fd,buffer,4096),"read")
		if n==0 then break end
		total=total+n; assert(total<=(limit or 1048576),"file exceeds limit")
		chunks[#chunks+1]=ffi.string(buffer,n)
	end
	return table.concat(chunks)
end
local function readat(dir,name,limit)
	local fd=C.openat(dir,name,bit.bor(RDONLY,NOFOLLOW,CLOEXEC,NONBLOCK))
	if fd<0 and ffi.errno()==2 then return nil end
	check(fd,"unsafe or inaccessible file")
	return withfd(fd,function(f) return contents(f,limit) end)
end
function M.read(path,limit)
	local dir,name=parent(path)
	return withfd(dir,function(d) return readat(d,name,limit) end)
end
function M.mkdir(path,mode)
	local dir,name=parent(path)
	withfd(dir,function(d)
		if C.mkdirat(d,name,mode or 448)<0 then assert(ffi.errno()==17,"mkdir failed") end
		check(C.fsync(d),"directory sync")
	end)
	local fd=directory(path); C.close(fd)
end
function M.files(path,suffix)
	local dir=directory(path)
	local stream=C.fdopendir(dir)
	if stream==nil then C.close(dir); error("opendir failed") end
	local names={}
	while true do
		local item=C.readdir(stream); if item==nil then break end
		local name=ffi.string(item.name)
		if name:sub(1,1)~="." and (not suffix or name:sub(-#suffix)==suffix) then names[#names+1]=name end
	end
	C.closedir(stream); table.sort(names); return names
end
local function write_file(dir,name,bytes,mode,hook)
	local fd=check(C.openat(dir,name,bit.bor(WRONLY,CREAT,EXCL,NOFOLLOW,CLOEXEC),ffi.cast("unsigned int",mode)),"create")
	withfd(fd,function(f)
		local offset=0
		while offset<#bytes do
			local n=check(C.write(f,bytes:sub(offset+1),#bytes-offset),"write"); assert(n>0,"short write"); offset=offset+n
		end
		hook("write"); check(C.fsync(f),"file sync"); hook("file-sync")
	end)
end
local function temporary(name)
	counter=counter+1; return "."..name.."-"..tostring(counter).."-"..tostring(math.floor(os.clock()*1000000))
end
function M.atomic(path,bytes,mode,hook)
	hook=hook or function() end
	local dir,name=parent(path)
	return withfd(dir,function(d)
		local tmp=temporary(name)
		local ok,err=pcall(function()
			write_file(d,tmp,bytes,mode or 384,hook)
			check(C.renameat(d,tmp,d,name),"rename"); hook("rename")
			check(C.fsync(d),"directory sync"); hook("directory-sync")
		end)
		C.unlinkat(d,tmp,0)
		if not ok then error(err,0) end
	end)
end
function M.sync(path)
	local dir,name=parent(path)
	withfd(dir,function(d)
		local fd=check(C.openat(d,name,bit.bor(RDONLY,NOFOLLOW,CLOEXEC)),"sync open")
		withfd(fd,function(f) check(C.fsync(f),"file sync") end)
		check(C.fsync(d),"directory sync")
	end)
end
function M.chmod(path,mode)
	local dir,name=parent(path)
	withfd(dir,function(d)
		local fd=check(C.openat(d,name,bit.bor(RDONLY,NOFOLLOW,CLOEXEC)),"chmod open")
		withfd(fd,function(f) check(C.fchmod(f,mode),"chmod") end)
	end)
end
function M.route(path)
	local fd,identity=directory(path); C.close(fd)
	return {path=path,identity=identity}
end
local function sync_effects(effects)
	return effects and effects.sync or function(fd,kind) check(C.fsync(fd),kind.." sync") end
end
local function durable_match(dir,name,bytes,sync)
	local fd=check(C.openat(dir,name,bit.bor(RDONLY,NOFOLLOW,CLOEXEC,NONBLOCK)),"matching file open")
	return withfd(fd,function(f)
		if contents(f)~=bytes then return false end
		sync(f,"file"); sync(dir,"directory"); return true
	end)
end
function M.probe(route,id,bytes,effects)
	local ok,result=pcall(function()
		local fd,identity=directory(route.path)
		return withfd(fd,function(d)
			assert(identity==route.identity,"route changed")
			local found=readat(d,id..".frontmatter.md")
			if found==bytes then return durable_match(d,id..".frontmatter.md",bytes,sync_effects(effects)) and "matching" or "conflict" end
			return not found and "missing" or "conflict"
		end)
	end)
	return ok and result or "conflict"
end
function M.publish(route,id,bytes,effects)
	assert(id:match("^[%w_%-]+$"),"unsafe delivery identifier")
	local published=false
	local sync=sync_effects(effects)
	local link=effects and effects.link or C.linkat
	local ok,result=pcall(function()
		local fd,identity=directory(route.path)
		return withfd(fd,function(d)
			assert(identity==route.identity,"route changed")
			local name=id..".frontmatter.md"
			local existing_ok,existing=pcall(readat,d,name)
			if not existing_ok then return "conflict" end
			if existing then
				if existing==bytes then
					published=true
					return durable_match(d,name,bytes,sync) and "matching" or "conflict"
				end
				return "conflict"
			end
			local tmp=temporary(name)
			local worked,why=pcall(function()
				write_file(d,tmp,bytes,384,function() end)
				if link(d,tmp,d,name,0)<0 then
					if ffi.errno()==17 then
						if readat(d,name)==bytes then
							published=true
							return durable_match(d,name,bytes,sync) and "matching" or "conflict"
						end
						return "conflict"
					end
					error("link failed")
				end
				published=true
				sync(d,"directory")
				return "published"
			end)
			C.unlinkat(d,tmp,0)
			if not worked then error(why,0) end
			return why
		end)
	end)
	return ok and result or published and "uncertain" or "retry"
end
function M.unlink(path)
	local dir,name=parent(path); withfd(dir,function(d) check(C.unlinkat(d,name,0),"unlink"); check(C.fsync(d),"directory sync") end)
end
function M.private_config(path)
	local dir,name=parent(path)
	return withfd(dir,function(d)
		local fd=check(C.openat(d,name,bit.bor(RDONLY,NOFOLLOW,CLOEXEC,NONBLOCK)),"config open")
		return withfd(fd,function(f)
			local s=info(f)
			assert((s.uid==0 or s.uid==C.geteuid()) and bit.band(s.mode,18)==0,"config must be owner-controlled")
			return contents(f,1048576)
		end)
	end)
end
-- Advisory exclusive flock on PATH, returning an unlock closure or nil when another process holds it.
-- Nonblocking by default; WAIT blocks until the holder releases, so processes that a timer wake-up
-- coalesces (the checkup sampler and its delivery retry) serialize instead of one of them failing.
function M.lock(path,wait)
	local dir,name=parent(path)
	local fd=withfd(dir,function(d) return check(C.openat(d,name,bit.bor(WRONLY,CREAT,NOFOLLOW,CLOEXEC),ffi.cast("unsigned int",384)),"lock open") end)
	if C.flock(fd,wait and 2 or 6)<0 then C.close(fd); return nil end
	return function() C.close(fd) end
end
return M
