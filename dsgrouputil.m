/*!
 * dsgrouputil.m
 * dsgrouputil
 *
 * Copyright (c) 2010 Ben Gollmer.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 * http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/network/IONetworkController.h>
#import <OpenDirectory/OpenDirectory.h>

#define VERSION "1.0.0"

NSString * const kDSGUCommandCheckMember      = @"checkmember";
NSString * const kDSGUCommandEnumerate        = @"enumerate";

NSString * const kDSGUMemberTypeUser          = @"user";
NSString * const kDSGUMemberTypeGroup         = @"group";
NSString * const kDSGUMemberTypeComputer      = @"computer";
NSString * const kDSGUMemberTypeComputerGroup = @"computergroup";

NSString *getHostUUID()
{
  uuid_t u;
  struct timespec t = { 0, 0 };
  char hwuuid[36];
  
  gethostuuid(u, &t);
  uuid_unparse_upper(u, hwuuid);
  
  return [NSString stringWithCString:hwuuid encoding:NSUTF8StringEncoding];
}

NSString *getEthernetAddress()
{
  kern_return_t kres;
  mach_port_t port;
  CFMutableDictionaryRef service_description = NULL;
  io_service_t service = 0, controller = 0;
  CFDataRef addr = NULL;
  NSString *ret = nil;
  
  kres = IOMasterPort(MACH_PORT_NULL, &port);
  if(kres != KERN_SUCCESS)
  {
    fprintf(stderr, "Error accessing IOKit: %d\n", kres);
    goto ex;
  }
  
  service_description = IOBSDNameMatching(port, 0, "en0");
  if(service_description == NULL)
  {
    fprintf(stderr, "Error locating ethernet device en0\n");
    goto ex;
  }
  
  service = IOServiceGetMatchingService(port, service_description);
  if(!service)
  {
    fprintf(stderr, "Error getting IOService for ethernet device en0\n");
    goto ex;
  }
  
  kres = IORegistryEntryGetParentEntry(service, kIOServicePlane, &controller);
  if(kres != KERN_SUCCESS)
  {
    fprintf(stderr, "Error accessing controller for ethernet device en0\n");
    goto ex;
  }
  
  addr = IORegistryEntryCreateCFProperty(controller,
                                         CFSTR(kIOMACAddress),
                                         kCFAllocatorDefault,
                                         0);
  
  const unsigned char *b = [(NSData *)addr bytes];
  ret =
    [NSString stringWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x",
      b[0], b[1], b[2], b[3], b[4], b[5]];
    
ex:
  if(service) IOObjectRelease(service);
  if(controller) IOObjectRelease(controller);
  if(addr != NULL) CFRelease(addr);
  return ret;
}

ODRecord *getRecord(ODNode *node,
                    ODRecordType recType,
                    ODAttributeType attr,
                    NSString *attr_val)
{
  ODQuery *q;
  NSArray *retattrs =
    [NSArray arrayWithObjects:
      kODAttributeTypeRecordName, kODAttributeTypeGUID, nil];
  

  q = [ODQuery queryWithNode:node
              forRecordTypes:recType
                   attribute:attr
                   matchType:kODMatchEqualTo
                 queryValues:attr_val
            returnAttributes:retattrs
              maximumResults:1
                       error:nil];
    
  return [[q resultsAllowingPartial:NO error:nil] lastObject];
}

ODRecord *getCurrentHostRecord(ODNode *node)
{
  ODRecord *host;
  
  /* Search by hardware UUID first */
  NSString *hwuuid = getHostUUID();
  if(hwuuid != nil)
  {
    host = getRecord(node, 
                     kODRecordTypeComputers,
                     kODAttributeTypeGUID,
                     hwuuid);
    if(host != nil) return host;
  }
  
  /* Can't find record by UUID, try ethernet addy */
  NSString *enetaddr = getEthernetAddress();
  if(enetaddr != nil)
  {
    host = getRecord(node,
                     kODRecordTypeComputers,
                     kODAttributeTypeENetAddress,
                     enetaddr);
    if(host != nil) return host;
  }
  
  /* No record found */
  return nil;
}

BOOL walkGroups(ODNode *node,
                ODRecord *member,
                ODRecordType memberType,
                ODRecordType groupType,
                NSString *compare)
{
  ODQuery *q;
  ODAttributeType attr;
  NSArray *retattrs =
    [NSArray arrayWithObjects:
      kODAttributeTypeRecordName, kODAttributeTypeGUID, nil];
  
  BOOL ret = NO;
  
  if(memberType == kODRecordTypeUsers || memberType == kODRecordTypeComputers)
  {
    attr = kODAttributeTypeGroupMembers;
  }
  else
  {
    attr = kODAttributeTypeNestedGroups;
  }
  
  NSString *mg =
    [[member valuesForAttribute:kODAttributeTypeGUID error:nil] lastObject];
  if(mg == nil) return NO;
  
  q = [ODQuery queryWithNode:node
              forRecordTypes:groupType
                   attribute:attr
                   matchType:kODMatchEqualTo
                 queryValues:mg
            returnAttributes:retattrs
              maximumResults:INT_MAX
                       error:nil];
  for(ODRecord *r in [q resultsAllowingPartial:NO error:nil])
  {
    if(compare != nil) 
    {
      NSString *rg =
        [[r valuesForAttribute:kODAttributeTypeGUID error:nil] lastObject];
      if(rg != nil && [rg isEqualToString:compare]) return YES;
    }
    else
    {
      fprintf(stdout, "%s\n", [r.recordName UTF8String]);
    }
    
    ret = ret || walkGroups(node, r, r.recordType, groupType, compare);
  }
  
  return ret;
}

  
void usage()
{
  fprintf(stderr,
"\ndsgrouputil %s - Retrieve group and computer group membership.\n\n", VERSION);
  
  fprintf(stderr,
"Operations:\n"
"    -o checkmember    Checks group membership.\n"
"    -o enumerate      Enumerates all groups a given member belongs to.\n\n"
"Options:\n"
"    -n  [node]        DirectoryService node to work with. Defaults to /Search.\n"
"    -t  [membertype]  Type of member - user, group, computer, or computergroup\n\n"
"Specifying members:\n"
"    -m  [member]      Short name of member\n"
"    -mu [guid]        GUID of member\n"
"    -me [enetaddr]    Ethernet address of member - only valid for computer\n"
"                      member type\n"
"    -currentHost 1    Use the current computer record; only valid for computer\n"
"                      member type\n\n"
"Specifying groups:\n"
"    -g  [group]       Short name of group\n"
"    -gu [guid]        GUID of group\n\n"
"Other options:\n"
"    -q 1              Don't print to stdout during -o checkmember; exit \n"
"                      status 0 will be set if member belongs to the specified\n"
"                      group\n\n");
  
  exit(254);
}

int main(int argc, const char * argv[])
{
  NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
  NSUserDefaults *args = [NSUserDefaults standardUserDefaults];
  NSError *err;
  
  NSString *cmd = [args stringForKey:@"o"];
  NSString *nodeName = [args stringForKey:@"n"];
  NSString *memberTypeName = [args stringForKey:@"t"];
  
  ODRecord *member = nil, *group = nil;
  
  if(cmd == nil)
  {
    fprintf(stderr, "Must specify command with -o\n");
    usage();
  }
  
  if(memberTypeName == nil)
  {
    fprintf(stderr, "Must specify member type with -t\n");
    usage();
  }
  
  if(nodeName == nil) nodeName = @"/Search";
  ODSession *session = [ODSession defaultSession];
  ODNode *node = [ODNode nodeWithSession:session name:nodeName error:&err];
  if(node == nil)
  {
    fprintf(stderr, "Error opening node %s\n", [nodeName UTF8String]);
    if(err != nil)
    {
      fprintf(stderr, "%s\n", [[err localizedDescription] UTF8String]);
    }
    
    return 1;
  }
  
  /* Determine member type */
  ODRecordType memberType = nil, groupType = nil;
  if([memberTypeName isEqualToString:kDSGUMemberTypeComputer])
  {
    memberType = kODRecordTypeComputers;
    groupType = kODRecordTypeComputerGroups;
  }
  else if([memberTypeName isEqualToString:kDSGUMemberTypeComputerGroup])
  {
    memberType = kODRecordTypeComputerGroups;
    groupType = kODRecordTypeComputerGroups;
  }
  else if([memberTypeName isEqualToString:kDSGUMemberTypeUser])
  {
    memberType = kODRecordTypeUsers;
    groupType = kODRecordTypeGroups;
  }
  else if([memberTypeName isEqualToString:kDSGUMemberTypeGroup])
  {
    memberType = kODRecordTypeGroups;
    groupType = kODRecordTypeGroups;
  }
  
  if(memberType == nil || groupType == nil)
  {
    fprintf(stderr,
      "Invalid member type - use user, group, computer, or computergroup\n");
    usage();
  }
  
  NSString *memberGUID = [args stringForKey:@"mu"];
  NSString *memberEnetAddress = [args stringForKey:@"me"];
  NSString *memberName = [args stringForKey:@"m"];
  
  if(![args boolForKey:@"currentHost"] &&
     memberGUID == nil && memberEnetAddress == nil && memberName == nil)
  {
    fprintf(stderr, "Must specify member with -m, -me, -mu, or -currentHost\n");
    usage();
  }
  
  NSString *groupGUID = [args stringForKey:@"gu"];
  NSString *groupName = [args stringForKey:@"g"];
  
  BOOL checkmember = NO;
  if([cmd isEqualToString:kDSGUCommandCheckMember])
  {
    checkmember = YES;
  }
  else if ([cmd isEqualToString:kDSGUCommandEnumerate])
  {
    checkmember = NO;
  }
  else
  {
    fprintf(stderr, "Invalid command; use -o checkmember or -o enumerate\n");
    usage();
  }
  
  if(checkmember && (groupGUID == nil && groupName == nil))
  {
    fprintf(stderr, "Must specify group with -g or -gu\n");
    usage();
  }
  
  /* Get member record */
  if([args boolForKey:@"currentHost"])
  {
    if(memberType != kODRecordTypeComputers)
    {
      fprintf(stderr,
  "Specifying member with -currentHost only valid for computer member type\n");
      usage();
    }
    
    member = getCurrentHostRecord(node);
    if(member == nil)
    {
      fprintf(stderr,
              "Can't find computer record for current host in node %s\n",
              [nodeName UTF8String]);
      return 2;
    }
  }
  else if(memberGUID != nil)
  {
    member = getRecord(node,
                       memberType,
                       kODAttributeTypeGUID,
                       memberGUID);
    if(member == nil)
    {
      fprintf(stderr,
              "Can't find %s record for GUID %s in node %s\n",
              [memberTypeName UTF8String],
              [memberGUID UTF8String],
              [nodeName UTF8String]);
      return 3;
    }
  }
  else if(memberEnetAddress != nil)
  {
    if(memberType != kODRecordTypeComputers)
    {
      fprintf(stderr,
    "Specifying member by enet address only valid for computer member type\n");
      usage();
    }
    
    member = getRecord(node,
                       memberType,
                       kODAttributeTypeENetAddress,
                       memberEnetAddress);
    if(member == nil)
    {
      fprintf(stderr,
              "Can't find computer record for enet address %s in node %s\n",
              [memberEnetAddress UTF8String],
              [nodeName UTF8String]);
      return 4;
    }
  }
  else if(memberName != nil)
  {
    member = getRecord(node,
                       memberType,
                       kODAttributeTypeRecordName,
                       memberName);
    if(member == nil)
    {
      fprintf(stderr,
              "Can't find %s record for %s in node %s\n",
              [memberTypeName UTF8String],
              [memberName UTF8String],
              [nodeName UTF8String]);
      return 5;
    }
  }
  
  /* Get group record */
  if(groupGUID != nil)
  {
    group = getRecord(node,
                      groupType,
                      kODAttributeTypeGUID,
                      groupGUID);
    if(group == nil)
    {
      fprintf(stderr,
              "Can't find %s record for GUID %s in node %s\n",
      (groupType == kODRecordTypeComputerGroups) ? "computergroup" : "group",
              [groupGUID UTF8String],
              [nodeName UTF8String]);
      return 6;
    }
  }
  else if(groupName != nil)
  {
    group = getRecord(node,
                      groupType,
                      kODAttributeTypeRecordName,
                      groupName);
    if(group == nil)
    {
      fprintf(stderr,
              "Can't find %s record %s in node %s\n",
      (groupType == kODRecordTypeComputerGroups) ? "computergroup" : "group",
              [groupName UTF8String],
              [nodeName UTF8String]);
      return 7;
    }
  }
  
  if(checkmember)
  {
    NSString *compare =
      [[group valuesForAttribute:kODAttributeTypeGUID error:nil] lastObject];
    
    BOOL m = walkGroups(node, member, memberType, groupType, compare);
    if(![args boolForKey:@"q"])
    {
      fprintf(stdout,
              "%s %s %s a member of %s %s\n",
              [memberTypeName UTF8String],
              [member.recordName UTF8String],
              (m) ? "is" : "is *not*",
              (groupType == kODRecordTypeGroups) ? "group" : "computergroup",
              [group.recordName UTF8String]);
    }
    
    return (m) ? 0 : 255;
  }
  else
  {
    fprintf(stdout,
            "%s %s is a member of %s:\n",
            [memberTypeName UTF8String],
            [member.recordName UTF8String],
            (groupType == kODRecordTypeGroups) ? "groups" : "computergroups");
    walkGroups(node, member, memberType, groupType, nil);
  }
  
  [pool drain];
  return 0;
}
